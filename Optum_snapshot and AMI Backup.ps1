# Assumptions :
# 1. server will have preconfigured AWS Client

Add-Type -AssemblyName System.IO.Compression.FileSystem

$env:Path = $env:Path + ";C:\Program Files\Amazon\AWSCLI\"

# fetching instance meta data
$curl = New-Object System.Net.WebClient
$instaceMetaData = $curl.DownloadString("http://169.254.169.254/latest/dynamic/instance-identity/document")
$jsonMetaData = $instaceMetaData | ConvertFrom-Json
$instanceID = $jsonMetaData.instanceId
$availabilityZone = $jsonMetaData.availabilityZone
$region = $jsonMetaData.region

$logFile ="C:\Users\Administrator\AMI-Log\disaster-recovery-$(Get-Date -format 'M-d-yyyy-hh-mm-ss').log"
Write-Output "Insntace ID : $instanceID" | Out-File $logFile -Append 
Write-Output "Region : $region" | Out-File $logFile -Append 
Write-Output "Availabilicy Zone : $availabilityZone" | Out-File $logFile -Append 

$volume_list = @()
$snapshot_list = @()
$today = Get-Date -format yyyy-MM-dd
$retention_days=30

############# Part 1: Create Snapshot and Delete the snapshots Older than 30 Days ###########################

function snapshot_volumes ()
{ 
    foreach ($volume_id in $volume_list) {

        $letter = get_drive_letter($volume_id)
        $description="$letter-Optum_backup-$today"

        # Take a snapshot of the current volume, and capture the resulting snapshot ID
        $snapresult = aws ec2 create-snapshot --region $region --output=text --description $description --volume-id $volume_id --query SnapshotId
        Write-Output "Newly created Snappshot ID : $snapresult Created for $instanceID" | Out-File $logFile -Append 

        # And then we're going to add a "CreatedBy:AutomatedBackup" tag to the resulting snapshot.
        # Why? Because we only want to purge snapshots taken by the script later, and not delete snapshots manually taken.

        aws ec2 create-tags --region $region --resource $snapresult --tags Key="CreatedBy,Value=AutomatedBackup"
        aws ec2 create-tags --region $region --resource $snapresult --tags Key="timestamp,Value=$today"
      
        
    }
}

function get_drive_letter($volId) 
{
    # Much of this function was pulled from Powershell code in the AWS documentation at
    # http://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2-windows-volumes.html
    # Get the drive letter for the volume ID that was passed in

    # Create a hash table that maps each device to a SCSI target
    $Map = @{"0" = '/dev/sda1'} 
    for($x = 1; $x -le 26; $x++) {$Map.add($x.ToString(), [String]::Format("xvd{0}",[char](97 + $x)))}
    for($x = 78; $x -le 102; $x++) {$Map.add($x.ToString(), [String]::Format("xvdc{0}",[char](19 + $x)))}

    #Get the volumes attached to this instance
    $BlockDeviceMappings = (Get-EC2Instance  -StoredCredentials coupadev -Region $region -Instance $instanceID).Instances.BlockDeviceMappings

    $drives = Get-WmiObject -Class Win32_DiskDrive | % {
        $Drive = $_
        # Find the partitions for this drive
        Get-WmiObject -Class Win32_DiskDriveToDiskPartition |  Where-Object {$_.Antecedent -eq $Drive.Path.Path} | %{
            $D2P = $_
            # Get details about each partition
            $Partition = Get-WmiObject -Class Win32_DiskPartition |  Where-Object {$_.Path.Path -eq $D2P.Dependent}
            # Find the drive that this partition is linked to
            $Disk = Get-WmiObject -Class Win32_LogicalDiskToPartition | Where-Object {$_.Antecedent -in $D2P.Dependent} | %{ 
                $L2P = $_
                #Get the drive letter for this partition, if there is one
                Get-WmiObject -Class Win32_LogicalDisk | Where-Object {$_.Path.Path -in $L2P.Dependent}
            }
            $BlockDeviceMapping = $BlockDeviceMappings | Where-Object {$_.DeviceName -eq $Map[$Drive.SCSITargetId.ToString()]}
           
            # Display the information in a table
            New-Object PSObject -Property @{
                Device = $Map[$Drive.SCSITargetId.ToString()];
                Disk = [Int]::Parse($Partition.Name.Split(",")[0].Replace("Disk #",""));
                Boot = $Partition.BootPartition;
                Partition = [Int]::Parse($Partition.Name.Split(",")[1].Replace(" Partition #",""));
                SCSITarget = $Drive.SCSITargetId;
                DriveLetter = If($Disk -eq $NULL) {"NA"} else {$Disk.DeviceID};
                VolumeName = If($Disk -eq $NULL) {"NA"} else {$Disk.VolumeName};
                VolumeId = If($BlockDeviceMapping -eq $NULL) {"NA"} else {$BlockDeviceMapping.Ebs.VolumeId}
            }
        }
    }
    foreach ($d in $drives) {
        if ($volId -eq $d.VolumeId) {
            $driveletter = $d.DriveLetter
        }
    }
    return $driveletter
}

$volume_list = aws ec2 describe-volumes --region $region --filters Name="attachment.instance-id,Values=$instanceID" --query Volumes[].VolumeId --output text | %{$_.split("`t")
}
    
snapshot_volumes

# Delete all attached volume snapshots created by this script that are older than $retention_days
function cleanup_snapshots() {

$logFile ="C:\Users\Administrator\SnapshotDeletion-Log\Deletedon-$(Get-Date -format 'M-d-yyyy-hh-mm-ss').log"
$retention_days = 30
$today = Get-Date

            
            foreach($volume_id in $volume_list){

            $snapshot_list = aws ec2 describe-snapshots --region $region --output=text --filters 'Name=description,Values="C:-Optum_backup-2017*"'"Name=volume-id,Values=$volume_id" "Name=tag:CreatedBy,Values=AutomatedBackup" --query Snapshots[].SnapshotId | %{$_.split("`t")}

            foreach($snapshot_id in $snapshot_list)
             {
            $snapshot_date = aws ec2 describe-snapshots --region $region --output=text --snapshot-ids $snapshot_id --query Snapshots[].StartTime | %{$_.split('T')[0]}
            $snapshot_age = (get-date $today) - (get-date $snapshot_date)  | select-object Days | foreach {$_.Days}
        
            if ($snapshot_age -gt $retention_days) 
            {
                aws ec2 delete-snapshot --region $region --snapshot-id $snapshot_id
                 Write-Output "Snapshot Deleted : $snapshot_id  for $instanceID" | Out-File $logFile -Append
            }

            else 
            {
                Write-Output "Snapshot Not Deleted : $snapshot_id  for $instanceID" | Out-File $logFile -Append
            }
        }
    }
}

cleanup_snapshots


##################################### Part-1 Ends ############################################################

######################### Part-2 Create AMI and Delete AMI older than 30 days ################################


#Description: Creates an Amazon Web Service AMI for a given instance Id
#Returns: string - newly created amiID
function createAMIForInstance([string] $volumeID, [string] $instanceName)
{    
    try
    {
        Write-Output "Instance $instanceID Creating new AMI" | Out-File $logFile -Append   
        $timeStamp = Get-Date -format yyyyMMddss           
        $amiID = aws ec2 create-image --instance-id $instanceID --name "optum-dev-$(Get-Date -format yyyyMMddss)" --no-reboot
        Write-Output "Newly created AMI ID : $amiID Created for $instanceID" | Out-File $logFile -Append
        
    }
    catch [Exception]
    {
        $function = "createAMIForInstance"
        $exception = $_.Exception.ToString()
        Write-Output "$function : AMI for Instance $amiID failed, Exception:" | Out-File $logFile -Append 
        Write-Output "function: $exception" -isException $true | Out-File $logFile -Append 
    }
}

$instanceInfo = aws ec2 describe-instances --instance-ids $instanceID --region $region
$instanceInfo = -join $instanceInfo | ConvertFrom-Json
$instanceName = $instanceInfo | %{$_.Reservations.Instances[0].Tags} | Where-Object {$_.Key -eq 'Name'} | %{$_.value}

Write-Output "Instance Name : $instanceName" | Out-File $logFile -Append
$rootDeviceName = $instanceInfo | %{$_.Reservations.Instances[0].RootDeviceName}
Write-Output "Root Device Name : $rootDeviceName" | Out-File $logFile -Append
$rootVolumeInfo = $instanceInfo.Reservations.Instances.BlockDeviceMappings | where-object {$_.DeviceName -eq $rootDeviceName }
$volumeID = $rootVolumeInfo.Ebs.VolumeId
Write-Output "Root Volume ID : $volumeID" | Out-File $logFile -Append



createAMIForInstance $volumeID $instanceName


## Function Declarations

# Check if an event log source for this script exists; create one if it doesn't.
function logsetup {
    if (!([System.Diagnostics.EventLog]::SourceExists('EBS-AMI')))
        { New-Eventlog -LogName "Application" -Source "EBS-AMI" }
}

# Write to console and Application event log (event ID: 1337)
function log ($type) {
    Write-Host $global:log_message
    Write-EventLog -LogName Application -Source "EBS-AMI" -EntryType $type -EventID 1337 -Message $global:log_message
}

#### Script to Delete Old AMI which are older than 30 Days ####
## Set User-Defined Variables
# How many days do you wish to retain backups for? Default: 7 days


## Set Variables
Set-StrictMode -Version Latest
$nl = [Environment]::NewLine
$instance_list=@()
$volume_list = @()
$AMI_List = @()
$global:log_message = $null
$hostname = hostname

$curl = New-Object System.Net.WebClient
$instance_id = $curl.DownloadString("http://169.254.169.254/latest/meta-data/instance-id")
$region = $curl.DownloadString("http://169.254.169.254/latest/meta-data/placement/availability-zone")
$region = $region.Substring(0,$region.Length-1)

function cleanupAMI(){

    $amisList = aws ec2 describe-images --filters "Name=platform,Values= windows" "Name=name,Values=optum-dev-2017*"
    $amisList = -join $amisList | ConvertFrom-Json
    $retention_days = 30
    $today = Get-Date
    $logFile ="C:\Users\Administrator\AMIDeletion-Log\Deletedon-$(Get-Date -format 'M-d-yyyy-hh-mm-ss').log"
    foreach($ami in  $amisList.Images )
     {
        $amiAge = (get-date $today) - (get-date $ami.CreationDate)  | select-object Days | foreach {$_.Days}
        $amiID = $ami.ImageId
        if ($amiAge -gt $retention_days)
     {
            aws ec2 deregister-image --image-id $amiID
                Write-Output "Deleting AMI  $amiID ..."| Out-File $logFile -Append
         }
        else
     {
            Write-Output "Not deleting AMI  $amiID ..." | Out-File $logFile -Append
         }
         }
}

cleanupAMI


Write-host " ############ Script excuted sucessfully ################# "





