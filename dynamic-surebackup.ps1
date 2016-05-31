#
# Dynamic Surebackup v 2.0
#
####################################################################
#
# MIT License
#
#Copyright (c) 2016 Luca Dell'Oca
#
# Thanks to Hans Leysen for the major improvements
# in version 2.0
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

# Variables for script ------------------------
$AppGroupName = "Dynamic App Group"
$SbJobName = "Dynamic Surebackup Job"
$SbJobDesc = "Dynamic App Testing"
$Date = (get-date).AddDays(-30)
$VirtualLab = "Virtual Lab 1"
#Variables for function selectUntestedVMs
[string]$VeeamBackupCounterFile = ".\hashtable.xml"
[int]$NumberofVMs = 20
###############################################

# Functions ------------------------------
Function selectUntestedVMs
{
    param([string]$fVeeamBackupCounterFile,[int]$fNumberofVMs,$fVbrObjs)

    $fHashtable = @{}
    $fTestVMs = [System.Collections.ArrayList]@()
    $fDeletedVMs = [System.Collections.ArrayList]@()

    # Import VeeamBackupCounterfile if exists from a previous iteration
    if(Test-Path $fVeeamBackupCounterFile)
    {
        $fHashtable = import-clixml $fVeeamBackupCounterFile
    }

    # Check if all VM's were tested
    # if so the hashtable is cleared

    if(!($fHashtable.Values -contains 0))
    {
        $fHashtable = @{}
    }

    # Add newly created VM's from backup
    Foreach($fVbrObj in $fVbrObjs)
    {
        if(!($fHashtable.Contains($fVbrObj.name)))
        {
            $fHashtable.Add($fVbrObj.name, "0")
        }
    }

    # Remove old VM's from hashtable
    $fHashtable.getEnumerator() | %{ if($fVbrObjs.name -notcontains $_.name) {$fDeletedVMs += $_.name}}
    $fDeletedVMs | foreach{ $fHashtable.Remove($_)}

    # Sort hashtable by Value
    # Used new object because sorting the hashtable converts it to dictionary entry
    $fHashtableOrdered = $fHashtable.GetEnumerator() | sort -Property "Value", "Name"

    # Select least tested VMs and increment their value to 1 (tested)
    for ($i = 0; $i -lt $fNumberofVMs; $i++)
    {
        $fTestVMs += $fHashtableOrdered[$i].Name
        $fHashtable.Set_Item($fHashtableOrdered[$i].Name, 1)
    }

    #Save hashtable to file for the next iteration
    $fHashtable | export-clixml $fVeeamBackupCounterFile

    Return $fTestVMs

}
##########################################

asnp "VeeamPSSnapIn" -ErrorAction SilentlyContinue

# Check if there is no dynamic surebackup job running
if(!(get-vsbjob -Name "Dynamic Surebackup Job"))
{

    # Find all VM objest successfully backed up in last 1 days
    $VbrObjs = (Get-VBRBackupSession | ?{$_.JobType -eq "Backup" -and $_.EndTime -ge $Date}).GetTaskSessions() | ?{$_.Status -eq "Success" -or $_.Status -eq "Warning" }
    # Call function selectUntestedVMs
    $TestVMs = selectUntestedVMs -fVeeamBackupCounterFile $VeeamBackupCounterFile -fNumberofVMs $NumberofVMs -fVbrObjs $VbrObjs

    # Create the new App Group, SureBackup Job, Start the Job
    $VirtualLab = Get-VSBVirtualLab -Name $VirtualLab
    $AppGroup = Add-VSBViApplicationGroup -Name $AppGroupName -VmFromBackup (Find-VBRViEntity -Name $TestVMs)
    $VsbJob = Add-VSBJob -Name $SbJobName -VirtualLab $VirtualLab -AppGroup $AppGroup -Description $SbJobDesc

    Start-VSBJob -Job $VsbJob

    # Remove the old App Group
    Remove-VSBJob -Job (Get-VSBJob -Name $SbJobName) -Confirm:$false
    Remove-VSBApplicationGroup -AppGroup (Get-VSBApplicationGroup -Name $AppGroupName) -Confirm:$false
}
