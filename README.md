# Optum-Backup-Automation
Optum AMI and Snapshot Backup Creation
aws-ec2-ebs-automatic-snapshot-powershell

####Powershell script for Automatic AMI and EBS Snapshots and Cleanup on Amazon Web Services (AWS) EC2

===================================

How it works: These scripts will:

Determine the instance ID of the EC2 server on which the script runs.
Gather a list of all volume IDs attached to that instance.
Take a snapshot of each attached volume
The script will then delete all associated snapshots taken by the script that are older than 30 days
The script will create AMI of the instance
The script will delete all associated AMI created by the script which are older than 30 days
Pull requests greatly welcomed!

===================================

REQUIREMENTS

IAM: This script requires that an IAM User or IAM Role be created with the following policy attached:

{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1426256275000",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSnapshot",
                "ec2:CreateTags",
                "ec2:DeleteSnapshot",
                "ec2:DescribeSnapshots",
                "ec2:DescribeVolumes",
                "ec2:DescribeInstances"
                "ec:CreateAMI",
                "ec2 deregister-image"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}

**AWS CLI:** This script requires the AWS CLI tools to be installed on the target Windows instance.
Log into your Windows instance with your local Administrator account.

Download the Windows installer for AWS CLI at: [https://aws.amazon.com/cli/] (https://aws.amazon.com/cli/)

Next, open a command prompt on the Window server and configure the AWS CLI (Note: you can skip this step if your EC2 instance is configured with an IAM role):

C:\Users\Administrator> aws configure

AWS Access Key ID: (Enter in the IAM credentials generated above.)
AWS Secret Access Key: (Enter in the IAM credentials generated above.)
Default region name: (The region that this instance is in: i.e. us-east-1, eu-west-1, etc.)
Default output format: (Enter "text".)

**INSTALL SCRIPT AS A SCHEDULED TASK**
[Download the scripts from Github] (https://github.com/coupa-ops/ws-ec2-ebs-automatic-snapshot-powershell/archive/master.zip)

Extract the zip contents to C:\aws on your Windows Server

Next, open Task Scheduler on the server, and create a new task that runs:

powershell.exe -ExecutionPolicy Bypass -file "C:\Users\Administrator\Optum_ProHealth\Optum_Final.ps1"
...on a nightly basis.

===================================

TROUBLESHOOTING

If you setup the AWS CLI under a Windows user account other than the local Administrator, you will need to edit the file "2-run-backup.cmd", and change the USERPROFILE path.

For example, let's say that you've configured the AWS CLI credentials under the Windows user account "myadmin". You will need to:

Open C:\aws\2-run-backup.cmd in Notepad
Change "set USERPROFILE=C:\Users\Administrator" to "set USERPROFILE=C:\Users\myadmin"
Save and exit.
