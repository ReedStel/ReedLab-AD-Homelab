@{
    LabName = 'ReedLab'

    Domain = @{
        Fqdn              = 'corp.reedlab.test'
        NetBIOS           = 'REEDLAB'
        DistinguishedName = 'DC=corp,DC=reedlab,DC=test'
        ForestMode        = 'WinThreshold'
        DomainMode        = 'WinThreshold'
    }

    Network = @{
        Prefix       = '10.50.0.0/24'
        Gateway      = '10.50.0.1'
        DnsServer    = '10.50.0.10'
        DhcpStart    = '10.50.0.100'
        DhcpEnd      = '10.50.0.199'
        DhcpScopeId  = '10.50.0.0'
        SubnetMask   = '255.255.255.0'
    }

    Computers = @{
        DomainController = @{ Name = 'LAB-DC01'; Address = '10.50.0.10' }
        FileServer       = @{ Name = 'LAB-SRV01'; Address = '10.50.0.20' }
        Client01         = @{ Name = 'LAB-CL01';  Address = '10.50.0.101' }
        Client02         = @{ Name = 'LAB-CL02';  Address = '10.50.0.102' }
    }

    OrganizationalUnits = @(
        @{ Name = 'ReedLab';          Parent = 'DC=corp,DC=reedlab,DC=test' }
        @{ Name = 'Users';            Parent = 'OU=ReedLab,DC=corp,DC=reedlab,DC=test' }
        @{ Name = 'Engineering';      Parent = 'OU=Users,OU=ReedLab,DC=corp,DC=reedlab,DC=test' }
        @{ Name = 'Operations';       Parent = 'OU=Users,OU=ReedLab,DC=corp,DC=reedlab,DC=test' }
        @{ Name = 'Finance';          Parent = 'OU=Users,OU=ReedLab,DC=corp,DC=reedlab,DC=test' }
        @{ Name = 'People';           Parent = 'OU=Users,OU=ReedLab,DC=corp,DC=reedlab,DC=test' }
        @{ Name = 'Admin Accounts';   Parent = 'OU=ReedLab,DC=corp,DC=reedlab,DC=test' }
        @{ Name = 'Service Accounts'; Parent = 'OU=ReedLab,DC=corp,DC=reedlab,DC=test' }
        @{ Name = 'Groups';           Parent = 'OU=ReedLab,DC=corp,DC=reedlab,DC=test' }
        @{ Name = 'Servers';          Parent = 'OU=ReedLab,DC=corp,DC=reedlab,DC=test' }
        @{ Name = 'Workstations';     Parent = 'OU=ReedLab,DC=corp,DC=reedlab,DC=test' }
        @{ Name = 'Quarantine';       Parent = 'OU=ReedLab,DC=corp,DC=reedlab,DC=test' }
    )

    Security = @{
        MinimumPasswordLength = 14
        PasswordHistoryCount  = 24
        MaximumPasswordAgeDays = 60
        LockoutThreshold       = 5
        LockoutMinutes         = 15
        LapsPasswordAgeDays    = 30
        LapsPasswordLength     = 20
    }

    Storage = @{
        SharesRoot = 'C:\Shares'
    }

    EventForwarding = @{
        CollectorName = 'LAB-SRV01'
        CollectorFqdn = 'LAB-SRV01.corp.reedlab.test'
        RefreshSeconds = 60
    }
}
