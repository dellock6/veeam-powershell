#
# Veeam Backup Job Creator
#
####################################################################
#
# MIT License
#
#Copyright (c) 2016 Luca Dell'Oca
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
####################################################################

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
