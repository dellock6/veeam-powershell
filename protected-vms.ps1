#
# Verify protected VM's
#
# Luca Dell'Oca - https://github.com/dellock6
# Released under GPL 3.0 license
#
# Run the script against vCenter and Veeam server and checks which VM's
# have been protected in the last 23 hours, and which are not protected

asnp "VeeamPSSnapIn" -ErrorAction SilentlyContinue

####################################################################
# Configuration
# vCenter server
$vcenter = "vcenter_ip_or_fqdn"
# To Exclude VMs from report add VM names to be excluded as follows
# $excludevms=@("vm1","vm2")
$excludevms=@()
####################################################################

$vcenterobj = Get-VBRServer -Name $vcenter
$vmobjs = Find-VBRObject -Server $vcenterobj | Where-Object {$_.Type -eq "VirtualMachine"}
$jobobjids = [Veeam.Backup.Core.CHierarchyObj]::GetObjectsOnHost($vcenterobj.id) | Where-Object {$_.GetItem().Type -eq "Vm"}

# Convert exclusion list to simple regular expression
$excludevms_regex = (‘(?i)^(‘ + (($excludevms |foreach {[regex]::escape($_)}) –join “|”) + ‘)$’) -replace "\\\*", ".*"

foreach ($vm in $vmobjs) {
    $jobobjid = ($jobobjids | Where-Object {$_.ObjectId -eq $vm.Id}).Id
    if (!$jobobjid) {
        $jobobjid = $vm.FindParent("Datacenter").Id + "\" + $vm.Id
    }
    $vm | Add-Member -MemberType NoteProperty "JobObjId" -Value $jobobjid
}    

# Get a list of all VMs from vCenter and add to hash table, assume Unprotected
$vms=@{}
foreach ($vm in ($vmobjs | where {$_.Name -notmatch $excludevms_regex}))  {
	if(!$vms.ContainsKey($vm.JobObjId)) {
		$vms.Add($vm.JobObjId, @("!", [string]$vm.GetParent("Datacenter"), $vm.Name))
    }
}

# Find all backup job sessions that have ended in the last 24 hours (change 24 to have a different time period)
$vbrjobs = Get-VBRJob | Where-Object {$_.JobType -eq "Backup"}
$vbrsessions = Get-VBRBackupSession | Where-Object {$_.JobType -eq "Backup" -and $_.EndTime -ge (Get-Date).addhours(-24)}

# Find all successfully backed up VMs in selected sessions (i.e. VMs not ending in failure) and update status to "Protected"
foreach ($session in $vbrsessions) {
    foreach ($vm in ($session.gettasksessions() | Where-Object {$_.Status -ne "Failed"} | ForEach-Object { $_ })) {
        if($vms.ContainsKey($vm.Info.ObjectId)) {
            $vms[$vm.Info.ObjectId][0]=$session.JobName
        }
    }
}

$vms = $vms.GetEnumerator() | Sort-Object Value

# Output VMs in color coded format based on status.
foreach ($vm in $vms)
{
  if ($vm.Value[0] -ne "!") {
      write-host -foregroundcolor green (($vm.Value[1]) + "\" + ($vm.Value[2])) "is backed up in job:" $vm.Value[0]
  } else {
      write-host -foregroundcolor red (($vm.Value[1]) + "\" + ($vm.Value[2])) "is not found in any backup session in the last 24 hours"
  }
}