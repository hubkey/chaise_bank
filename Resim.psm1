<#
Install:
    PS> Import-Module .\Resim.psm1 -Force -Verbose
Uninstall:
    PS> Remove-Module Resim -Verbose
#>

function Reset-Resim {
    <#
    .SYNOPSIS
        Resets resim
    .DESCRIPTION
    .EXAMPLE
        PS>Reset-Resim
    .EXAMPLE
        PS>rr
    #>
    [CmdletBinding()]
    param ()
    begin {
        Write-Verbose "Processing started at $((Get-Date).ToString('o'))"
    }
    process {
        resim reset
    }
    end {
        Write-Verbose "Processing complete at $((Get-Date).ToString('o'))"
    }
}

function SingleMatchOrThrow {
    param
    (
        [Parameter(Position=0)]
        [string]$InputString,
        
        [Parameter(Position=1)]
        [string]$Pattern
    )

    if (($InputString -match $Pattern) -ne $true)
    {
        throw "Could not match input string '$InputString' with regex pattern '$Pattern'"
    }
    if ($Matches.Length -ne 1)
    {
        throw "No unique match found"
    }
    $Matches[1]
}

class Account {
    [datetime] $Timestamp
    [string] $Component
    [string] $PublicKey
    [string] $PrivateKey

    Account() {
        $this.Timestamp = Get-Date
    }
}

function New-ResimAccount {
    <#
    .SYNOPSIS
        Adds a new Resim account and optionally set it as the default account
    .DESCRIPTION
    .EXAMPLE
        PS>New-ResimAccount
    .EXAMPLE
        PS>$Account = nra
    .EXAMPLE
        PS>$Account = nra $true
    #>
    [CmdletBinding()]
    [OutputType([Account])]
    param
    (
        [Parameter(Position=0, Mandatory=$false)]
        [switch]$SetDefault = $false
    )
    begin {
        Write-Verbose "Processing started at $((Get-Date).ToString('o'))"
    }
    process {
        $account = (resim new-account) -join "`n"

        Write-Verbose $account

        $pattern = @(
            "Account component address:\s(?<Component>[0-9a-f]+)"
            "Public key:\s(?<PublicKey>[0-9a-f]+)"
            "Private key:\s(?<PrivateKey>[0-9a-f]+)"
        ) -join "\s+"

        if ($account -match "(?ms)$pattern") { 

            $Matches.Remove(0) 
            $result = [Account]$Matches 

            if ($SetDefault -eq $true) {
                $null = Set-ResimAccount $result
            }

            $result
        
        } else { 
            throw "Could not match input string '$account' with regex pattern '$pattern'"
        }
    }
    end {
        Write-Verbose "Processing complete at $((Get-Date).ToString('o'))"
    }
}

function Set-ResimAccount {
    <#
    .SYNOPSIS
        Sets the default Resim account
    .DESCRIPTION
    .EXAMPLE
        PS>Set-ResimAccount $Account
    .EXAMPLE
        PS>sra $Account
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [Account]$Account
    )
    begin {
        Write-Verbose "Processing started at $((Get-Date).ToString('o'))"
    }
    process {
        resim set-default-account $Account.Component $Account.PrivateKey
    }
    end {
        Write-Verbose "Processing complete at $((Get-Date).ToString('o'))"
    }
}

function Publish-ResimPackage {
    <#
    .SYNOPSIS
        Publishes a Resim package
    .DESCRIPTION
    .EXAMPLE
        PS>Publish-ResimPackage
    .EXAMPLE
        PS>$Package = prp
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param ()
    begin {
        Write-Verbose "Processing started at $((Get-Date).ToString('o'))"
    }
    process {
        $package = (resim publish .) -join "`n"

        Write-Verbose $package

        SingleMatchOrThrow $package 'Success! New Package:\s([0-9a-f]+)'
    }
    end {
        Write-Verbose "Processing complete at $((Get-Date).ToString('o'))"
    }
}

function Invoke-Transaction {
    <#
    .SYNOPSIS
        Invokes a Resim transaction
    .DESCRIPTION
    .EXAMPLE
        PS>Invoke-Transaction 'ASSERT_WORKTOP_CONTAINS ResourceAddress("foo");'
    .EXAMPLE
        PS>rt 'ASSERT_WORKTOP_CONTAINS ResourceAddress("foo");'
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [string]$Transaction
    )
    begin {
        Write-Verbose "Processing started at $((Get-Date).ToString('o'))"
    }
    process {
        $tempFile = New-TemporaryFile

        $rtmFile = $tempFile -Replace '\.tmp$','.rtm'
        
        Rename-Item -Path $tempFile -NewName $rtmFile

        Set-Content -Path $rtmFile -Value $Transaction
        
        resim run $rtmFile
       
        Remove-Item -Path $rtmFile
    }
    end {
        Write-Verbose "Processing complete at $((Get-Date).ToString('o'))"
    }
}

function Get-ResourceAddress {
    <#
    .SYNOPSIS
        Gets a resource address by name
    .DESCRIPTION
    .EXAMPLE
        PS>Get-ResourceAddress $Account.Component "My badge"
    .EXAMPLE
        PS>gra $Account.Component "My badge"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [string]$Component,

        [Parameter(Position=1, Mandatory=$true)]
        [string]$Name
    )
    begin {
        Write-Verbose "Processing started at $((Get-Date).ToString('o'))"
    }
    process {
        $response = (resim show $Component) -join "`n"

        Write-Verbose $response

        $pattern = "resource address:\s(?<ResourceAddress>[0-9a-f]+),\sname:\s""$Name"""

        if ($response -match "(?ms)$pattern") { 

            $Matches["ResourceAddress"]
        
        } else { 
            throw "Could not match reponse '$response' with regex pattern '$pattern'"
        }
    }
    end {
        Write-Verbose "Processing complete at $((Get-Date).ToString('o'))"
    }
}

New-Alias -Name rr -Value Reset-Resim
New-Alias -Name nra -Value New-ResimAccount
New-Alias -Name prp -Value Publish-ResimPackage
New-Alias -Name sra -Value Set-ResimAccount
New-Alias -Name rt -Value Invoke-Transaction
New-Alias -Name gra -Value Get-ResourceAddress

Export-ModuleMember -Function Reset-Resim -Alias rr
Export-ModuleMember -Function New-ResimAccount -Alias nra
Export-ModuleMember -Function Publish-ResimPackage -Alias prp
Export-ModuleMember -Function Set-ResimAccount -Alias sra
Export-ModuleMember -Function Invoke-Transaction -Alias rt
Export-ModuleMember -Function Get-ResourceAddress -Alias gra