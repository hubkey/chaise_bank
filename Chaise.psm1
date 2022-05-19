<#
Install:
    PS> Import-Module .\Chaise.psm1 -Force -Verbose
Uninstall:
    PS> Remove-Module Chaise -Verbose
#>
Using module .\Resim.psm1

function New-Bank {
    <#
    .SYNOPSIS
        Creates and initilizes a new bank
    .DESCRIPTION
    .EXAMPLE
        PS>New-Bank $Package
    .EXAMPLE
        PS>nb $Package
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [string]$Package,

        [Parameter(Position=1, Mandatory=$false)]
        [decimal]$InitalFund = 100000,

        [Parameter(Position=2, Mandatory=$false)]
        [string]$InitalFundResourceAddress = "030000000000000000000000000000000000000000000000000004"
    )
    begin {
        Write-Verbose "Processing started at $((Get-Date).ToString('o'))"
    }
    process {
        $response = (resim call-function $Package Bank new "$InitalFund,$InitalFundResourceAddress") -join "`n"

        Write-Verbose $response

        $pattern = "Component:\s(?<Component>[0-9a-f]+)"

        if ($response -match "(?ms)$pattern") { 

            $Matches["Component"]
        
        } else { 
            throw "Could not match reponse '$response' with regex pattern '$pattern'"
        }
    }
    end {
        Write-Verbose "Processing complete at $((Get-Date).ToString('o'))"
    }
}

function Get-CustomerId {
    <#
    .SYNOPSIS
        Gets a customer ID
    .DESCRIPTION
    .EXAMPLE
        PS>Get-CustomerId $customer.Component "Customer badge"
    .EXAMPLE
        PS>gcid $customer.Component "Customer badge"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [string]$Component,

        [Parameter(Position=1, Mandatory=$false)]
        [string]$Name = "Customer badge"
    )
    begin {
        Write-Verbose "Processing started at $((Get-Date).ToString('o'))"
    }
    process {
        $response = (resim show $Component) -join "`n"

        Write-Verbose $response

        $pattern = "resource address:\s(?<ResourceAddress>[0-9a-f]+),\sname:\s""$Name"".*\sid:\s(?<Id>[0-9a-f]+),\s"

        if ($response -match "(?ms)$pattern") { 

            $Matches["Id"]
        
        } else { 
            throw "Could not match reponse '$response' with regex pattern '$pattern'"
        }
    }
    end {
        Write-Verbose "Processing complete at $((Get-Date).ToString('o'))"
    }
}

function Set-CustomerKnown {
    <#
    .SYNOPSIS
        Set a customer as known
    .DESCRIPTION
    .EXAMPLE
        PS>Set-CustomerKnown $owner.Component $bankComponent $customerId
    .EXAMPLE
        PS>sck $owner.Component $component $bankComponent $customerId
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [string]$AdminComponent,

        [Parameter(Position=1, Mandatory=$true)]
        [string]$BankComponent,

        [Parameter(Position=2, Mandatory=$true)]
        [string]$CustomerId
    )
    begin {
        Write-Verbose "Processing started at $((Get-Date).ToString('o'))"
    }
    process {
        $adminBadge = gra $AdminComponent "Bank admin badge"

        $transaction = @"

        CALL_METHOD 
            ComponentAddress("$AdminComponent") 
            "create_proof"
            ResourceAddress("$adminBadge");

        CALL_METHOD 
            ComponentAddress("$BankComponent") 
            "set_customer_known"
            NonFungibleId("$CustomerId");

"@

        Write-Verbose $transaction

        Invoke-Transaction $transaction
    }
    end {
        Write-Verbose "Processing complete at $((Get-Date).ToString('o'))"
    }
}

function Get-Customer {
    <#
    .SYNOPSIS
        Gets a customer
    .DESCRIPTION
    .EXAMPLE
        PS>Get-Customer $owner.Component $bankComponent $customerId
    .EXAMPLE
        PS>gcust $owner.Component $bankComponent $customerId
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [string]$AdminComponent,

        [Parameter(Position=1, Mandatory=$true)]
        [string]$BankComponent,

        [Parameter(Position=2, Mandatory=$true)]
        [string]$CustomerId
    )
    begin {
        Write-Verbose "Processing started at $((Get-Date).ToString('o'))"
    }
    process {
        $adminBadge = Get-ResourceAddress $AdminComponent "Bank admin badge"

        $transaction = @"

        CALL_METHOD 
            ComponentAddress("$AdminComponent") 
            "create_proof"
            ResourceAddress("$adminBadge");

        CALL_METHOD 
            ComponentAddress("$BankComponent") 
            "customer"
            NonFungibleId("$CustomerId");

"@

        Write-Verbose $transaction

        Invoke-Transaction $transaction
    }
    end {
        Write-Verbose "Processing complete at $((Get-Date).ToString('o'))"
    }
}

function Invoke-Deposit {
    <#
    .SYNOPSIS
        Deposits XRD to a customer bank account
    .DESCRIPTION
    .EXAMPLE
        PS>Invoke-Deposit $bankComponent $customer.Component 1000
    .EXAMPLE
        PS>deposit $bankComponent $customer.Component 1000
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [string]$BankComponent,

        [Parameter(Position=1, Mandatory=$true)]
        [string]$CustomerComponent,

        [Parameter(Position=2, Mandatory=$true)]
        [decimal]$Amount
    )
    begin {
        Write-Verbose "Processing started at $((Get-Date).ToString('o'))"
    }
    process {
        $customerBadge = Get-ResourceAddress $CustomerComponent "Customer badge"

        $transaction = @"

        CALL_METHOD ComponentAddress("$CustomerComponent") "create_proof_by_amount" Decimal("1") ResourceAddress("$customerBadge");

        CREATE_PROOF_FROM_AUTH_ZONE ResourceAddress("$customerBadge") Proof("customerBadge");

        CALL_METHOD ComponentAddress("$CustomerComponent") "withdraw_by_amount" Decimal("$Amount") ResourceAddress("030000000000000000000000000000000000000000000000000004");

        TAKE_FROM_WORKTOP_BY_AMOUNT Decimal("$Amount") ResourceAddress("030000000000000000000000000000000000000000000000000004") Bucket("xrd");

        CALL_METHOD ComponentAddress("$BankComponent") "deposit" Proof("customerBadge") Decimal("$Amount") Bucket("xrd");

        CALL_METHOD_WITH_ALL_RESOURCES ComponentAddress("$CustomerComponent") "deposit_batch";
"@

        Write-Verbose $transaction

        Invoke-Transaction $transaction
    }
    end {
        Write-Verbose "Processing complete at $((Get-Date).ToString('o'))"
    }
}

function Invoke-Withdraw {
    <#
    .SYNOPSIS
        Withdraws XRD from a customer bank account
    .DESCRIPTION
    .EXAMPLE
        PS>Invoke-Withdraw $bankComponent $customer.Component 1000
    .EXAMPLE
        PS>withdraw $bankComponent $customer.Component 1000
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [string]$BankComponent,

        [Parameter(Position=1, Mandatory=$true)]
        [string]$CustomerComponent,

        [Parameter(Position=2, Mandatory=$true)]
        [decimal]$Amount
    )
    begin {
        Write-Verbose "Processing started at $((Get-Date).ToString('o'))"
    }
    process {
        $customerBadge = Get-ResourceAddress $CustomerComponent "Customer badge"

        $transaction = @"

        CALL_METHOD ComponentAddress("$CustomerComponent") "create_proof_by_amount" Decimal("1") ResourceAddress("$customerBadge");

        CREATE_PROOF_FROM_AUTH_ZONE ResourceAddress("$customerBadge") Proof("customerBadge");

        CALL_METHOD ComponentAddress("$BankComponent") "withdraw" Proof("customerBadge") Decimal("$Amount");

        CALL_METHOD_WITH_ALL_RESOURCES ComponentAddress("$CustomerComponent") "deposit_batch";
"@

        Write-Verbose $transaction

        Invoke-Transaction $transaction
    }
    end {
        Write-Verbose "Processing complete at $((Get-Date).ToString('o'))"
    }
}

New-Alias -Name nb -Value New-Bank
New-Alias -Name sck -Value Set-CustomerKnown
New-Alias -Name gcid -Value Get-CustomerId
New-Alias -Name gcust -Value Get-Customer
New-Alias -Name deposit -Value Invoke-Deposit
New-Alias -Name withdraw -Value Invoke-Withdraw

Export-ModuleMember -Function New-Bank -Alias nb
Export-ModuleMember -Function Set-CustomerKnown -Alias sck
Export-ModuleMember -Function Get-CustomerId -Alias gcid
Export-ModuleMember -Function Get-Customer -Alias gcust
Export-ModuleMember -Function Invoke-Deposit -Alias deposit
Export-ModuleMember -Function Invoke-Withdraw -Alias withdraw
