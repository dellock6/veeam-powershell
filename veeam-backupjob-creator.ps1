#
# Veeam Backup Job Creator
#
# Luca Dell'Oca - https://github.com/dellock6
# Released under GPL 3.0 license
#

#Retrieve the list of existing datastores as we want to create one job per datastore

asnp “VeeamPSSnapIn” -ErrorAction SilentlyContinue
Find-VBRViEntity -DatastoresAndVMs | where {$_.Type -eq “Datastore”} | select {$_.Name} -Unique | Sort-Object Name

# Ask for parameters and build the job
# The job uses a deduplication appliance, so we ask in which day to run the synthetic full

$datastorename = Read-Host ‘Which datastore you want to protect?’
$repositoryname = Read-Host ‘Which repository you want to use?’
$fullday = Read-Host ‘Which day you want to run the synthetic full? Options are Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday’
$time = Read-Host “At what time of the day you want to run the job? Format is hh:mm”

$VBRName = “This server”
$VBR = Get-VBRServer -Name $VBRName
$VC = Get-VBRServer -Type “VC”

$datastore = Find-VBRViDatastore -Server $VC -Name $datastorename
$repository = Get-VBRBackupRepository -Name $repositoryname

# Create the Backup job. We use the datastore name as the Backup job name

Add-VBRViBackupJob -Name $datastorename -Entity $datastore -BackupRepository $repository

# Job is created with default parameters
# After creation, the script edits the job options to have the final result

# Set retention points, change 7 if you want something different than 7 days

$job = Get-VBRJob -Name $datastorename
$options = $job.GetOptions()
$options.BackupStorageOptions.RetainCycles = 7
$job.SetOptions($options)

# for compression levels and block size = http://helpcenter.veeam.com/backup/80/powershell/set-vbrjobadvancedstorageoptions.html

Get-VBRJob -Name $datastorename | Set-VBRJobAdvancedStorageOptions -CompressionLevel 4 -EnableDeduplication $True -StorageBlockSize 6

# Disable default synthetic and set active full on the desired day.
# This can be used if the repository is not a supported deduplication
# appliance and you prefer to do active fulls

#Get-VBRJob -Name $datastorename | Set-VBRJobAdvancedBackupOptions -Algorithm Incremental -TransformFullToSyntethic $False -EnableFullBackup $True -FullBackupDays $fullday

# Set the schedule, daily execution with date as input, and enable it

Get-VBRJob -Name $datastorename | Set-VBRJobSchedule -Daily -At $time
Get-VBRJob -Name $datastorename | Enable-VBRJobSchedule

