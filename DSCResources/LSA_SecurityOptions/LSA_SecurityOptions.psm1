function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Enable
    )
    $ErrorActionPreference = 'Stop'
    #Write-Verbose "Use this cmdlet to deliver information about command processing."
    #Write-Debug "Use this cmdlet to write debug information while troubleshooting."
    
    $temp = "C:\Windows\security\database"
    $file = "$temp\cSecurityOptions_module_temppol.inf"
    $outHash = @{}

    $ps = new-object System.Diagnostics.Process
    $ps.StartInfo.Filename = "secedit.exe"
    $ps.StartInfo.Arguments = " /export /cfg $file /areas securitypolicy"
    $ps.StartInfo.RedirectStandardOutput = $True
    $ps.StartInfo.UseShellExecute = $false
    [void]$ps.start()
    [void]$ps.WaitForExit('10')
    [string] $process = $ps.StandardOutput.ReadToEnd();

    $in = get-content $file
    Remove-Item $file -Force

    # I now have the configuration options, now need to assemble into a hash table
    foreach ($line in $in)
    {
        if ($line.Contains("=") -and $line -notlike "Unicode*" -and $line -notlike "signature*" -and $line -notlike "Revision*" -and $line -notlike "Audit*")
        {
            if (!($line.Contains("MACHINE")))
            {
                <#
                $policy = $line.substring(0,$line.IndexOf("=") - 1)
                $values = ($line.substring($line.IndexOf("=") + 1,$line.Length - ($line.IndexOf("=") + 1))).trim()
                if ($values.Contains("`"")){
                    $outHash.Add($policy,($values.Substring(1)).substring(0,$values.Length - 2))
                } else {
                    $outHash.Add($policy,$values)
                }
                #>
            } else {
                # These are for registry settings
                if ($line.Contains("`""))
                {
                    $policy = $line.split("=")[0]
                    $values = $line.split("=")[1] -replace "`"", ""
                    $outHash.Add($policy,$values)
                } else {
                    $policy = $line.split("=")[0]
                    $values = $line.split("=")[1]
                    $outHash.Add($policy,$values)
                }
            }
        }
    }

    $returnValue = @{
                     Enable = $Enable
                     LSA_SecurityOptions = $outHash
                    }

    $returnValue
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Enable,

        [parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance[]]
        $LSA_SecurityOptions
    )
    $ErrorActionPreference = 'Stop'
    #Write-Verbose "Use this cmdlet to deliver information about command processing."
    #Write-Debug "Use this cmdlet to write debug information while troubleshooting."

    $temp = "C:\Windows\security\database"
    $newfile = "$temp\cSecurityOptions_module_newpol.inf"
    $new_secdb = "$temp\cSecurityOptions_secedit.sdb"
    
    if (test-path $newfile){Remove-Item $newfile -Force}
    
    "[Unicode]" | Out-File $newfile
    "Unicode=yes" | Out-File $newfile -Append
    "[Registry Values]" | Out-File $newfile -Append
    foreach ($configSecOption in $LSA_SecurityOptions.GetEnumerator())
    {
        #Write-Verbose "This is the full line: $($configSecOption)"
        $ValueParts = $configSecOption.Value.split(",")
        #Write-Verbose "What are the parts:  $($ValueParts[0])"
        <#
        if ($configSecOption.Value[0] -eq 1)
        {
            "$($configSecOption.Name)=$($configSecOption.Value[0])" + "," + "`"$($configSecOption.Value[1])`"" | Out-File $newfile -Append
        } elseif (($configSecOption.Value[0] -eq 7) -and (($configSecOption.Name).substring($configSecOption.Name.length - 15, 15) -eq 'LegalNoticeText')) {
            "$($configSecOption.Name)=$($configSecOption.Value[0])" + "," + "`"$($configSecOption.Value[1])`"" | Out-File $newfile -Append
        } else {
            "$($configSecOption.Name)=$($configSecOption.Value[0])" + "," + "$($configSecOption.Value[1])" | Out-File $newfile -Append
        }
        #>
        if ($ValueParts[0] -eq 1)
        {
            "$($configSecOption.Key)=$($ValueParts[0])" + "," + "`"$($ValueParts[1])`"" | Out-File $newfile -Append
        #} elseif (($ValueParts[0] -eq 7) -and (($configSecOption.Name).substring($configSecOption.Name.length - 15, 15) -eq 'LegalNoticeText')) {
        } elseif ($ValueParts[0] -eq 7) {
            #"$($configSecOption.Name)=$($ValueParts[0])" + "," + "`"$($ValueParts[1])`"" | Out-File $newfile -Append
            "$($configSecOption.Key)=$($ValueParts[0])" + "," + "`"$(($configSecOption.Value).Substring(2))`"" | Out-File $newfile -Append
        } else {
            "$($configSecOption.Key)=$($ValueParts[0])" + "," + "$($ValueParts[1])" | Out-File $newfile -Append
        }
    }
    "[Version]" | Out-File $newfile -Append
    "signature=`"`$CHICAGO`$`"" | Out-File $newfile -Append
    "Revision=1" | Out-File $newfile -Append
    
    $ps = new-object System.Diagnostics.Process
    $ps.StartInfo.Filename = "secedit.exe"
    $ps.StartInfo.Arguments = " /configure /db $new_secdb /cfg $newfile /overwrite /quiet"
    $ps.StartInfo.RedirectStandardOutput = $True
    $ps.StartInfo.UseShellExecute = $false
    [void]$ps.start()
    [void]$ps.WaitForExit('10')
    [string] $process = $ps.StandardOutput.ReadToEnd();

    Remove-Item $newfile -Force
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Enable,

        [parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance[]]
        $LSA_SecurityOptions
    )
    $ErrorActionPreference = 'Stop'
    #Write-Verbose "Use this cmdlet to deliver information about command processing."
    #Write-Debug "Use this cmdlet to write debug information while troubleshooting."
    
    $CurrentSetting = Get-TargetResource -Enable $true
    
    # Start with $true, assuming that there are no differences, but if there is a difference, flip it.
    # Set-TargetResource only is triggered on $false - should be seldom
    $diffFound = $true
    foreach ($regSecOption in $LSA_SecurityOptions.GetEnumerator())
    {
        # No longer need to loop through if any difference found - performance increase by stopping
        if ($diffFound -eq $false){break}
        #write-host "Reg Option: " $regSecOption.Name -BackgroundColor Blue
        foreach ($existConfig in $CurrentSetting.LSA_SecurityOptions.GetEnumerator())
        {
            #write-host "Existing Config Option: " $existConfig.Name -BackgroundColor Green
            if ($regSecOption.Key -eq $existConfig.Name)
            {
                #$regSecOptionConcat = $regSecOption.Value[0].toString() + "," + $regSecOption.Value[1].ToString()
                #write-host "RegSecOptionConcat: $($regSecOptionConcat)"
                #if ($regSecOptionConcat -ne $existConfig.Value)
                #{
                #    $diffFound = $false
                #}
                #write-host "Reg Option: " $regSecOption.Name -BackgroundColor Blue
                #write-host "Exist Option: " $existConfig.Name -BackgroundColor Green
                #write-host "RegSecOption: $($regSecOption.Value) & ExistConfig: $($existConfig.Value)"
                if ($regSecOption.Value -ne $existConfig.Value)
                {
                    $diffFound = $false
                    break
                }
            }
        }
    }

    Write-Verbose "This is the value: $($diffFound)"
    return $diffFound
}

Export-ModuleMember -Function *-TargetResource
