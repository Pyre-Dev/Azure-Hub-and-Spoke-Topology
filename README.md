# Azure Hub-and-Spoke Lab

Hub-and-spoke topology built across five independent Terraform sessions. Covers VNet peering,
Azure Firewall with UDR-forced egress, private DNS, Key Vault, NSGs, Log Analytics, and VNet
flow logs. Designed to pair with an ARM template repeat and a portal walkthrough.

---

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Terraform >= 1.3 installed
- An Azure subscription with Contributor access (Global Admin recommended for Session 3 Key Vault access policies)

No SSH keypair needed locally. Session 3 generates one inside Key Vault.

---

## Architecture

```
                    [ Internet ]
                         |
                   [ Azure Firewall ]  <-- pip-hub-firewall (Standard Static)
                         |
              [ Hub VNet: 10.0.0.0/16 ]
             /    AzureFirewallSubnet: 10.0.0.0/26  (no NSG - Azure restriction)
            /     GatewaySubnet:       10.0.1.0/27  (no NSG - Azure restriction)
           /      snet-management:     10.0.2.0/24  (NSG: deny internet, allow VNet)
          /         Key Vault PE  (10.0.2.x)
         /          Log Analytics PE (10.0.2.x)
        / peering                  \ peering
       /                            \
[ Spoke 1: 10.1.0.0/16 ]     [ Spoke 2: 10.2.0.0/16 ]
  snet-workload: 10.1.0.0/24    snet-workload: 10.2.0.0/24
  NSG: allow DNS, KV PE,        NSG: allow DNS, KV PE,
       VNet, firewall egress          VNet, firewall egress
  UDR: 0.0.0.0/0 -> Firewall   UDR: 0.0.0.0/0 -> Firewall
  Test VM (managed identity)
```

Key design points:
- VNet peering is NOT transitive. Spoke1 and Spoke2 cannot reach each other directly.
- All egress traffic from spokes is forced through Azure Firewall via UDR.
- BGP route propagation is disabled on spoke route tables to prevent gateway routes from overriding UDRs.
- NSGs and the firewall provide layered defense: NSG handles Layer 4, firewall handles Layer 7.
- NSGs are not supported on AzureFirewallSubnet or GatewaySubnet - Azure will reject them.
- Key Vault and Log Analytics have no public endpoints. All access flows through private endpoints in snet-management.
- The test VM SSH key is generated inside Key Vault. The private key never appears in Terraform state or the repo.
- The test VM uses a system-assigned managed identity for secretless Key Vault access at runtime.

---

## Session 1: VNets, Peering, and NSGs

Deploys the hub VNet with three subnets, two spoke VNets, all four peering connections, and NSGs
on the three subnets that support them (snet-management, spoke1 snet-workload, spoke2 snet-workload).

```bash
cd session1
terraform init
terraform plan
terraform apply
```

Verify in the portal:
- Peering status shows "Connected" on both sides for each pair
- NSGs are attached to snet-management, spoke1 snet-workload, and spoke2 snet-workload
- AzureFirewallSubnet and GatewaySubnet have no NSG (Azure does not permit it)

---

## Session 2: Azure Firewall and UDRs

Deploys Azure Firewall into the hub and attaches route tables to spoke workload subnets.

Note: Azure Firewall takes 5-10 minutes to provision.

```bash
cd ../session2
terraform init
terraform plan
terraform apply
```

Key things to observe after apply:
- Route table on each spoke subnet shows 0.0.0.0/0 -> VirtualAppliance -> [firewall private IP]
- Firewall private IP is in the 10.0.0.0/26 range (AzureFirewallSubnet)
- BGP route propagation is disabled on both route tables

---

## Session 3: Private DNS and Key Vault

Deploys a private DNS zone for Key Vault linked to all three VNets, provisions Key Vault with a
private endpoint in snet-management, and generates an RSA 4096 SSH key pair inside Key Vault.

Public network access is denied at the vault level. The private key never leaves Key Vault and
never appears in Terraform state or the repository.

```bash
cd ../session3
terraform init
terraform plan -var="key_vault_name=kv-hub-<your-initials>"
terraform apply -var="key_vault_name=kv-hub-<your-initials>"
```

Key Vault names must be globally unique across all of Azure (3-24 chars, alphanumeric and hyphens).

> **Note - running Terraform from outside the VNets:** Because `public_network_access_enabled = false`,
> the vault blocks all data-plane operations from public IPs. If you are running Terraform from your
> local machine or Cloud Shell, the `azurerm_key_vault_key.ssh` creation step will fail with a network
> deny error. The session includes an `allowed_ip` variable for this scenario:
>
> ```bash
> terraform apply -var="key_vault_name=kv-hub-<your-initials>" -var="allowed_ip=$(curl -4 -s ifconfig.me)"
> ```
>
> Once the key is created, remove the `allowed_ip` var and run apply again to lock the vault back down.
> This is expected behavior - it proves the network lockdown is working.

Key things to observe after apply:
- Private endpoint in snet-management has an IP in the 10.0.2.0/24 range
- The DNS zone `privatelink.vaultcore.azure.net` has an A record pointing to that IP, created automatically by the private endpoint
- The vault is inaccessible from the public internet

Verify the A record from Cloud Shell or your terminal:

```bash
az network private-dns record-set a list --resource-group rg-hub-spoke-lab --zone-name privatelink.vaultcore.azure.net --output table
```

---

## Session 4: Firewall Rules and Test VM

Deploys application rules (FQDN-based HTTPS filtering), a DNS network rule, and a test VM in Spoke 1.

The VM SSH public key is read from Key Vault via Terraform data source - no plaintext key in
variables, CLI flags, or Terraform state. The VM gets a system-assigned managed identity so it
can retrieve secrets from Key Vault at runtime without any stored credentials.

```bash
cd ../session4
terraform init
terraform plan -var="key_vault_name=kv-hub-<your-initials>"
terraform apply -var="key_vault_name=kv-hub-<your-initials>"
```

### Connecting to the VM

The VM has no public IP. Use Azure Serial Console in the portal:

Portal > Virtual Machines > vm-test-spoke1 > Help > Serial Console

Serial Console does not support key-based auth. Set a password first:

```bash
az vm user update --resource-group rg-hub-spoke-lab --name vm-test-spoke1 --username azureuser --password <password-you-choose>
```

### Exporting the private key for SSH via Bastion

If you prefer SSH over Serial Console, export the private key from Key Vault:

```bash
mkdir -p ~/.ssh && az keyvault key download --vault-name kv-hub-<your-initials> --name lab-ssh-key --encoding PEM --file ~/.ssh/lab_key.pem && chmod 600 ~/.ssh/lab_key.pem
```

Run this from a Linux terminal or WSL. The `chmod` command does not exist on Windows.

### Verifying traffic flows through the firewall

From the VM (Serial Console):

```bash
# Should succeed - allowed by application rule
curl -I https://www.microsoft.com

# Should fail - not in the allow list, hits implicit deny
curl -I https://api.snapcraft.io

# Verify Key Vault FQDN resolves to a private IP (10.0.2.x), not the public vault address
nslookup kv-hub-<your-initials>.vault.azure.net
```

Check effective routes from your terminal (confirms UDR is active):

```bash
az network nic show-effective-route-table --resource-group rg-hub-spoke-lab --name nic-test-vm-spoke1 --output table
```

0.0.0.0/0 should show nextHopType "VirtualAppliance" with the firewall private IP as next hop.

### Verifying managed identity secret access from the VM

From the VM (Serial Console), authenticate via IMDS and call Key Vault with no credentials:

```bash
TOKEN=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net' -H 'Metadata:true' | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
curl -s -H "Authorization: Bearer $TOKEN" "https://kv-hub-<your-initials>.vault.azure.net/secrets?api-version=7.4"
```

### Verifying Key Vault SSH key and DNS in the portal

**Key Vault key proof:**
Portal > Key Vault > Keys > lab-ssh-key > current version. Shows key type RSA 4096 and confirms
the key exists inside the vault without ever being in your repo or state.

**Private DNS proof:**
Portal > Private DNS Zones > privatelink.vaultcore.azure.net > Record sets. The A record pointing
to 10.0.2.x was created automatically by the private endpoint.

Portal > Key Vault > Networking > Private endpoint connections. Shows pe-keyvault-hub with
Connection state: Approved. Click into the endpoint > DNS configuration to see the FQDN-to-private-IP mapping.

---

## Session 5: Log Analytics and VNet Flow Logs

Deploys a Log Analytics Workspace with a private endpoint in snet-management, two private DNS
zones for Log Analytics linked across all three VNets, firewall diagnostic settings scoped to
application and network rule logs, and VNet flow logs with Traffic Analytics for all three VNets.

> **Note on NSG flow logs:** Microsoft blocked creation of new NSG flow logs as of June 30 2025
> ahead of their September 2027 retirement. This session uses VNet flow logs, which is the current
> recommended replacement. VNet flow logs capture traffic at the VNet level rather than per-NSG,
> giving broader coverage with less configuration overhead.

> **Note on Network Watcher:** Azure automatically provisions a Network Watcher in each region
> when certain resources are created. If one already exists in eastus (likely under `NetworkWatcherRG`),
> the `azurerm_network_watcher` resource block will conflict. The session uses a data source instead,
> which reads the existing one automatically.

> **Note on private endpoint feature registration:** If your subscription has not previously used
> private endpoints you may need to register the feature first:
>
> ```bash
> az feature register --namespace Microsoft.Network --name AllowPrivateEndpoints && az provider register --namespace Microsoft.Network
> ```
>
> Check registration status with:
>
> ```bash
> az feature show --namespace Microsoft.Network --name AllowPrivateEndpoints --query properties.state
> ```
>
> Wait until it returns `Registered` before running apply. This can take 15-30 minutes.

```bash
cd ../session5
terraform init
terraform plan -var="storage_account_name=stflowlogs<your-initials>"
terraform apply -var="storage_account_name=stflowlogs<your-initials>"
```

Storage account names must be globally unique, 3-24 chars, lowercase alphanumeric only (no hyphens).

Key things to observe after apply:
- Log Analytics Workspace is deployed with no public endpoint exposure
- Two private DNS zones for Log Analytics are linked to all three VNets alongside the Key Vault zone from Session 3
- Three VNet flow logs are active, one per VNet, all feeding into the same workspace via Traffic Analytics
- Firewall diagnostic settings are live and will capture traffic immediately

### Verifying firewall logs in Log Analytics

Run the curl commands from Session 4 first to generate traffic, then give it 1-2 minutes.

Portal > Log Analytics Workspace > Logs:

```kql
// Application rule decisions - allow/deny per FQDN
AZFWApplicationRule
| where TimeGenerated > ago(1h)
| project TimeGenerated, SourceIp, Fqdn, Action, RuleCollection, Rule
| order by TimeGenerated desc
```

```kql
// Network rule decisions - DNS traffic from spoke VMs
AZFWNetworkRule
| where TimeGenerated > ago(1h)
| project TimeGenerated, SourceIp, DestinationIp, DestinationPort, Action
| order by TimeGenerated desc
```

You should see:
- `www.microsoft.com` with Action: Allow from 10.1.0.x
- `api.snapcraft.io` with Action: Deny from 10.1.0.x
- UDP 53 queries to 168.63.129.16 in the network rule log, generated when the VM resolved the Key Vault FQDN

### Verifying VNet flow logs in Log Analytics

Traffic Analytics processes data from the storage account buffer on a 10-minute interval, so
flow log data will lag behind the firewall logs by 10-15 minutes. Once available:

```kql
// VNet flow summary - traffic across all three VNets
AzureNetworkAnalytics_CL
| where TimeGenerated > ago(1h)
| where SubType_s == "FlowLog"
| project TimeGenerated, SrcIP_s, DestIP_s, DestPort_d, FlowStatus_s
| order by TimeGenerated desc
```

This is the key architectural difference from the firewall logs: the firewall sees Layer 7
(FQDNs, protocols, rule names), while VNet flow logs see Layer 4 (raw IPs and ports at the
VNet boundary). Together they give a complete picture of what traffic entered and left each VNet.

### Verifying private DNS for Log Analytics in the portal

Portal > Private DNS Zones. You should now see three zones total:
- `privatelink.vaultcore.azure.net` (Session 3)
- `privatelink.ods.opinsights.azure.com` (data ingestion endpoint)
- `privatelink.oms.opinsights.azure.com` (agent management endpoint)

Each zone should have VNet links to hub, spoke1, and spoke2, and A records pointing to private
IPs in snet-management (10.0.2.x), created automatically by the private endpoints.

---

## Teardown

Destroy in reverse session order to avoid dependency errors:

```bash
cd session5 && terraform destroy -var="storage_account_name=stflowlogs<your-initials>"
cd ../session4 && terraform destroy -var="key_vault_name=kv-hub-<your-initials>"
cd ../session3 && terraform destroy -var="key_vault_name=kv-hub-<your-initials>"
cd ../session2 && terraform destroy
cd ../session1 && terraform destroy
```

Or delete the entire resource group at once:

```bash
az group delete --name rg-hub-spoke-lab --yes --no-wait
```

---

## Estimated cost

| Resource              | Approx cost/hour |
|-----------------------|-----------------|
| Azure Firewall        | ~$1.25/hr        |
| Standard_B1s VM       | ~$0.01/hr        |
| Public IP (Standard)  | ~$0.004/hr       |
| Private Endpoints (3) | ~$0.03/hr        |
| Log Analytics         | ~$0.00/hr (pay per GB ingested, negligible for lab traffic) |
| Storage Account (LRS) | ~$0.00/hr (negligible for flow log volume) |
| Key Vault             | ~$0.00/hr (charged per operation, negligible) |

A full lab run across all five sessions should cost under $8 if torn down promptly.
VNets, subnets, peerings, route tables, NSGs, and private DNS zones are free.
