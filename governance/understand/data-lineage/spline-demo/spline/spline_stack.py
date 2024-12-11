from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_iam as iam,
    CfnOutput,
    CfnParameter
)
from constructs import Construct

with open("./spline/user_data.sh") as f:
    user_data_file = f.read()

class SplineStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        key_pair_name = CfnParameter(self, "KeyPairName", type="String", 
                                     description="The name of the key pair to use to allow SSH to EC2 instance")

        vpc = ec2.Vpc(self, "Vpc",
            max_azs=1,
            gateway_endpoints={
                "S3": ec2.GatewayVpcEndpointOptions(
                    service=ec2.GatewayVpcEndpointAwsService.S3
                )
            }                  
        )

        internal_security_group = ec2.SecurityGroup(self, "InternalSecurityGroup",
            vpc=vpc,
            description="Security Group to allow all self referencing traffic"
        )
        internal_security_group.add_ingress_rule(
            peer=internal_security_group,
            connection=ec2.Port.all_traffic()
        )   

        ec2_role = iam.Role(self, "Ec2Role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="EC2 role to allow SSM management",
            managed_policies=[iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")]
        )

        # Instance type
        instance = ec2.Instance(self, "Instance",
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            instance_type=ec2.InstanceType("t3.medium"),
            vpc = vpc,
            security_group=internal_security_group,
            role=ec2_role,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            key_pair=ec2.KeyPair.from_key_pair_name(self, "EC2KeyPair", 
                                                    key_pair_name=key_pair_name.value_as_string),
            # add user data from local file
            user_data=ec2.UserData.custom(user_data_file),
            user_data_causes_replacement=True
        )
        
        CfnOutput(self, "SplineServerInstanceId", value=instance.instance_id)
