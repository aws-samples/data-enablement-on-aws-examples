# MSK Replicator active-active example

This demo code deploys two MSK serverless clusters across two different regions, along with supporting infrastructure (VPCs, security groups, IAM roles and others) and MSK replicators in both regions to provide an active-active setup. 

## Deploy 

The code will deploy infrastructure across two regions that will be referred to as region A and region B. You can specify desired regions in ```terraform.tfvars``` but ensure you use regions that support the required services and features and that contain required prerequisites (notably EC2 key pairs). 

### Architecture

Key resources deployed in both regions: 
* MSK serverless cluster
* MSK replicator 
* EC2 client configured to run [Conduktor](https://conduktor.io/) to allow management of each MSK cluster 

The use of Conduktor is to provide quick access to create and send sample data to topics for testing. It is optional in this sample, you can use alternate Kafka clients but the sample code configures the MSK clusters for IAM authentication only. 

### Prerequisites 

* Terraform 
* AWS CLI
* [AWS CLI session manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
* EC2 key pairs in both regions to support EC2 access 

### Process 

* Set desired parameter values in ```terraform.tfvars```. This currently has some sample values populated. EC2 key name refers to an EC2 key pair you have in that region. You must have this key locally too, since we will use this in establishing a connection to the EC2 instance. 
* Run ```terraform init``` 
* Run ```terraform apply```. Ensure you are happy with the resources deployed. Please note, this is sample code only. Some of the IAM resources include wildcards for all access and lack resource or similar constraints. This should be addressed before further use. 
* After resources have been created, terraform will output the instance ids of the Conduktor client EC2 instances in each region. We can use these to connect to the Conduktor UI using Systems Manager. This will allow us to view, create and send sample data to topics in each cluster to test the active-active replication. 
* In ```main.tf``` both MSK replicators are configured to use identical topic naming when replicating topics. This is not generally reccommended as it adds additional load, however it avoids the need reconfigure clients. If desired, you can switch to alternate strategy of prefixing topic names. See [Create an active-active setup using MSK Replicator](https://docs.aws.amazon.com/msk/latest/developerguide/msk-replicator-active-active.html) for more information. 


### Connect to MSK cluster with Conduktor client

In each region, an EC2 instance should be deployed with Conduktor installed. Connect to this instance using Systems Manager (because the instance is in a private subnet). To do this, use the EC2 instance ids returned by Terraform, or retrieve from the AWS console. Define a local SSH config to allow the use of port forwarding to be able to access the Conduktor UI from your local browser. An example SSH config on macOS is shown as per the following:
```
Host conduktor-client-region-a
	HostName <conduktor_client_instance_id_a>
	LocalForward 8080 localhost:8080
	User ubuntu
	IdentityFile <path_to_region_a_key>
	ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --region <aws_region_a>

Host conduktor-client-region-b
	HostName <conduktor_client_instance_id_b>
	LocalForward 8080 localhost:8080
	User ubuntu
	IdentityFile <path_to_region_b_key>
	ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --region <aws_region_b>
```

**Note** the Proxy command is using the AWS cli and systems manager plugin to connect to the instance in a private subnet, without the need to open security groups. Ensure these are set up as prerequisites to connect using this method. 

Ensure you replace:
* *<conduktor_client_instance_id_a>* with the instance id from region A
* *<path_to_region_a_key>* with a path to the local SSH key corresponding to the key used to launch the EC2 instance in region A
* *<aws_region_a>* with the relevant region, for example *eu-west-1*.

Do the same for the *conduktor-client-region-b* config, using the relevant values for region B. 

We should then be able to connect to these instances by running ```ssh conduktor-client-region-a``` in your terminal (ensure your AWS credentials are still valid). 

This will give terminal on the EC2 instance and you should also be able to navigate on local browser to localhost:8080 and view Conduktor UI. 

After closing the connection, you can do the same to connect to the instance in Region B, using ```ssh conduktor-client-region-b```. 

**NOTE** If you can't access the Conduktor UI, you may need to restart it. On the terminal while connected to your EC2 instance, navigate to */opt/app* then use docker compose to start the app. 
```
cd /opt/app
sudo docker compose up -d
```

This will restart the service and allow you to use the Conduktor UI locally. 

Use Conduktor in both regions to connect to the MSK cluster in the respective region and create topics and send sample data. Doing this from either region should result in the replication automatically syncing this data to the other cluster. Switch between the different regions to ensure this is functioning as expected. 

**NOTE** When creating cluster configurations in Conduktor, you can use IAM user access keys or preferably credentials inherited from the environment. Ensure credentials permit the use of kafka APIs. 

You should find that as you create and update data in one cluster, it is automatically replicated in the other, whichever way around you make these changes. 

## Clean up

After running through the sample code and exploring active-active replication, remove any related resources by running ```terraform destroy```. 