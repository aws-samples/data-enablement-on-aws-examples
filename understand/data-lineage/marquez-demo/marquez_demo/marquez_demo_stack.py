from aws_cdk import (
    # Duration,
    Stack,
    aws_ec2 as ec2,
    aws_eks as eks,
    aws_iam as iam,
    aws_rds as rds,
    CfnOutput,
    CfnParameter
)
from aws_cdk.lambda_layer_kubectl_v29 import KubectlV29Layer
from constructs import Construct

class MarquezDemoStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # parameters 
        eks_fargate_profile_name = CfnParameter(self, "EKSFargateProfileName", 
            type="String", 
            description="The name of the EKS Fargate Profile",
            default="marquez-profile"
        )

        eks_fargate_namespace_selector = CfnParameter(self, "EKSFargateNamespaceSelector", 
            type="String", 
            description="The name of the EKS Fargate Profile namespace selector",
            default="marquez"
        )

        key_pair_name = CfnParameter(self, "KeyPairName", type="String", 
            description="The name of the key pair to use to allow SSH to EC2 instance"
        )
        
        
        vpc = ec2.Vpc(self, "Vpc",
            max_azs=3,
            gateway_endpoints={
                "S3": ec2.GatewayVpcEndpointOptions(
                    service=ec2.GatewayVpcEndpointAwsService.S3
                )
            }
        )
        vpc.add_interface_endpoint(
            "SSMInterface",
            service=ec2.InterfaceVpcEndpointAwsService.SSM,
            private_dns_enabled=True
        )
        vpc.add_interface_endpoint(
            "SSMMessagesInterface",
            service=ec2.InterfaceVpcEndpointAwsService.SSM_MESSAGES,
            private_dns_enabled=True
        )
        vpc.add_interface_endpoint(
            "EC2MessagesInterface",
            service=ec2.InterfaceVpcEndpointAwsService.EC2_MESSAGES,
            private_dns_enabled=True
        )

        internal_security_group = ec2.SecurityGroup(self, "SelfRefSecurityGroup",
            vpc=vpc,
            description="SG to allow all self referencing traffic"
        )
        internal_security_group.add_ingress_rule(
            peer=internal_security_group,
            connection=ec2.Port.all_traffic()
        ) 
        # add VPC CIDR to allowed inbound security group
        internal_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(vpc.vpc_cidr_block),
            connection=ec2.Port.all_traffic()
        )

        # EKS Role
        eks_cluster_role = iam.Role(self, "EKSClusterRole",
            assumed_by=iam.ServicePrincipal("eks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSClusterPolicy")
            ]
        )

        # EKS Cluster
        eks_cluster = eks.FargateCluster(self, "EKSFargateCluster",
            role=eks_cluster_role,
            version=eks.KubernetesVersion.V1_29,
            vpc=vpc,
            security_group=internal_security_group,
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            kubectl_layer=KubectlV29Layer(self, "KubectlLayer"),
            # aws load balancer controller
            alb_controller=eks.AlbControllerOptions(
                version=eks.AlbControllerVersion.V2_5_1
            ),
            cluster_logging=[
                eks.ClusterLoggingTypes.API, 
                eks.ClusterLoggingTypes.AUTHENTICATOR, 
                eks.ClusterLoggingTypes.SCHEDULER
            ]
        )

        # Fargate profile 
        # when k8s pods are deployed with criteria that match the criteria 
        # defined in the profile, the pods are deployed to fargate 

        # AmazonEKSFargatePodExecutionRole
        eks_fargate_pod_execution_role = iam.Role(self, "EKSFargatePodExecutionRole",
            assumed_by=iam.ServicePrincipal("eks-fargate-pods.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSFargatePodExecutionRolePolicy")
            ]
        )

        eks_fargate_profile = eks.FargateProfile(self, "EKSFargateProfile",
            cluster=eks_cluster,
            fargate_profile_name=eks_fargate_profile_name.value_as_string,
            pod_execution_role=eks_fargate_pod_execution_role,
            vpc=vpc,
            # currently only private supported
            subnet_selection=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS), 
            selectors=[
                eks.Selector(namespace=eks_fargate_namespace_selector.value_as_string)
            ]
        )

        # add service account to EKS cluster for interaction with AWS API
        service_account = eks_cluster.add_service_account("EKSServiceAccount",
            name="service-account",
            namespace="default"
        )
        # data_bucket.grant_read_write(service_account)

        secret = rds.DatabaseSecret(self, "RDSDatabaseSecret",
            username="marquez",
            exclude_characters='” %,\+~`#$&*()|\'[]{}:;<>?!’/@”"',
            replace_on_password_criteria_changes=True
        )

        # rds db cluster
        db_cluster = rds.DatabaseCluster(self, "RDSDatabaseCluster",
            engine=rds.DatabaseClusterEngine.aurora_postgres(version=rds.AuroraPostgresEngineVersion.VER_15_4),
            instance_props=rds.InstanceProps(
                vpc=vpc,
                vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
                security_groups=[internal_security_group]
            ),
            instances=1,
            credentials=rds.Credentials.from_secret(secret),
            default_database_name="marquez"
        )

        ec2_role = iam.Role(self, "Ec2Role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="EC2 role to allow SSM management",
            managed_policies=[iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")]
        )

        # Instance type
        client_instance = ec2.Instance(self, "ClientInstance",
            machine_image=ec2.MachineImage.latest_amazon_linux2023(),
            instance_type=ec2.InstanceType("t3.medium"),
            vpc = vpc,
            security_group=internal_security_group,
            role=ec2_role,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            key_pair=ec2.KeyPair.from_key_pair_name(self, "EC2KeyPair", 
                key_pair_name=key_pair_name.value_as_string
            )
        )
    
        CfnOutput(self, "SecurityGroupId", value=internal_security_group.security_group_id)
        CfnOutput(self, "ClientInstanceId", value=client_instance.instance_id)
        CfnOutput(self, "EKSClusterName", value=eks_cluster.cluster_name)
        CfnOutput(self, "RDSSecretARN", value=secret.secret_arn)
