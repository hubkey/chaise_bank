#Import-Module .\Resim.psm1 -force
#Import-Module .\Chaise.psm1 -force

<# Usage example:

PS> $result = .\Setup.ps1
PS> $result.PSObject.Properties | ForEach-Object { Set-Variable -Name $_.Name -Value $_.Value }
PS> resim show $bankComponent
PS> resim set-default-account $owner.Component $owner.PrivateKey
PS> Get-Customer $owner.Component $bankComponent $customerId

#>

function RunSetup() {

    Reset-Resim
    
    resim set-current-epoch 1

    $owner = New-ResimAccount $true
    
    $package = Publish-ResimPackage
    
    # Create bank
    $bankComponent = New-Bank $package

    $ownerBadge = Get-ResourceAddress $owner.Component "Bank admin badge"

    # Create customer and switch account to newly created customer
    $customer = New-ResimAccount $true

    # Register as customer with bank. Returned bucket with customer badge (NFT) is automatically saved.
    $null = resim call-method $bankComponent customer_registration "Satoshi", "Nakamoto"

    $customerBadge = Get-ResourceAddress $customer.Component "Customer badge"

    # Switch back to owner account
    $null = resim set-default-account $owner.Component $owner.PrivateKey

    # Lookup customer id from badge of customer
    $customerId = Get-CustomerId $customer.Component

    # Set customer as known customer using proof of Admin badge ownership.
    Set-CustomerKnown $owner.Component $bankComponent $customerId

    # Switch back to customer account
    $null = resim set-default-account $customer.Component $customer.PrivateKey

    # Deposit 1000 XRD
    Invoke-Deposit $bankComponent $customer.Component 1000

    # Advance epoch
    resim set-current-epoch 2

    # Deposit another 1000 XRD
    Invoke-Deposit $bankComponent $customer.Component 1000

    # Advance epoch
    resim set-current-epoch 3

    # Withdraw 2500 XRD
    Invoke-Withdraw $bankComponent $customer.Component 2500

    [PSCustomObject]@{
        Package       = $package
        BankComponent = $bankComponent
        Owner         = $owner
        OwnerBadge    = $ownerBadge
        Customer      = $customer
        CustomerId    = $customerId
        CustomerBadge = $customerBadge
    }
}

(RunSetup)[-1]

