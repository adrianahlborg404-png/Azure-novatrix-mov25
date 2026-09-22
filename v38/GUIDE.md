# v38 – Snabbguide (G-nivå): Novatrix-infrastruktur som ARM-template

**Tidsåtgång:** cirka 20–30 minuter. **Kostnad:** i princip noll, eftersom ingen VM skapas.

Mallen skapar ett storage account med containern `arenden`, en NSG med webbregel för port 80 och 443, och ett VNet med subnätet `snet-public` där NSG:n är kopplad. Namn och region styrs med parametrar.

---

## 🔧 Förutsättningar (kontrollera snabbt)

- Du har ett Azure-konto med minst **Contributor**. Det har du haft sedan v34.
- **Git** är installerat och ditt repo `Azure-novatrix-mov25` är klonat lokalt.
- Repot är **publikt** på GitHub.
- Din **v34-VM** i `RG-novatrix` finns kvar. Den behövs för att visa formuläret i steg 3.

Du behöver ingen SSH-nyckel, IP-adress eller extra kvot.

---

## Steg 2 – Deploya från Cloud Shell

Öppna <https://shell.azure.com> och välj **Bash**:

```bash
cd ~
git clone https://github.com/adrianahlborg404-png/Azure-novatrix-mov25.git
cd Azure-novatrix-mov25/v38
bash deploy.sh
```

Har du klonat repot tidigare, kör i stället: `cd ~/Azure-novatrix-mov25 && git pull && cd v38 && bash deploy.sh`

Skriptet skapar resursgruppen `rg-novatrix-iac` och kör **what-if**. Du ska se **5 resurser med `+ Create`**: storage account, blobService, container, NSG och VNet.

📸 **1:** what-if-utskriften.

Svara `j` på frågan. Deployen tar under en minut och skriver sedan ut outputs.

📸 **2:** outputs.

Spara storage-namnet från outputs:

```bash
ST=<storageAccountName>
```

---

## Steg 3 – Verifiera att miljön blev som avsett

**Lagringen:** ladda upp en testfil och lista innehållet i containern.

```bash
echo '{"test":"v38 IaC"}' > test-arende.json
az storage blob upload --account-name $ST -c arenden -f test-arende.json -n test/arende.json --auth-mode key
az storage blob list   --account-name $ST -c arenden --auth-mode key -o table
```

📸 **3:** blob-listan med `test/arende.json`.

**Nätverket:** lista NSG-reglerna och subnätet.

```bash
az network nsg rule list -g rg-novatrix-iac --nsg-name nsg-novatrix-public -o table
az network vnet subnet list -g rg-novatrix-iac --vnet-name vnet-novatrix \
  --query "[].{namn:name, prefix:addressPrefix, nsg:networkSecurityGroup.id}" -o table
```

📸 **4:** regeln `Allow-Web-Inbound` (80/443) och `snet-public` med NSG:n kopplad.

**Formuläret:** VM:en ingår inte i G-mallen, så formuläret körs på din v34-VM. Starta den om den är stoppad:

```bash
az vm start -g RG-novatrix -n VM-novatrix-web
```

Öppna sedan sidan i webbläsaren.

📸 **5:** formuläret i webbläsaren.

---

## Steg 4 – Versionshantering: lägg till ett privat subnät

### 4.1 Gör ändringen lokalt i `v38/templates/azuredeploy.json`

**a)** Lägg till en ny parameter direkt efter `publicSubnetPrefix`:

```json
    "privateSubnetPrefix": {
      "type": "string",
      "defaultValue": "10.20.2.0/24",
      "metadata": { "description": "Adressrymd for det privata subnatet." }
    },
```

**b)** Lägg till en ny variabel. Sätt ett kommatecken efter `"subnetPublicName": "snet-public"` och lägg sedan till:

```json
    "subnetPrivateName": "snet-private"
```

**c)** I VNet-resursens `subnets`: sätt ett kommatecken efter `snet-public`-objektets avslutande `}` och lägg till:

```json
          {
            "name": "[variables('subnetPrivateName')]",
            "properties": {
              "addressPrefix": "[parameters('privateSubnetPrefix')]"
            }
          }
```

VS Code markerar med rött om ett kommatecken saknas eller är för mycket.

### 4.2 Committa och pusha

```bash
git add v38/templates/azuredeploy.json
git commit -m "v38: privat subnät i VNet:et"
git push origin Master
```

### 4.3 Deploya ändringen i Cloud Shell

```bash
cd ~/Azure-novatrix-mov25 && git pull && cd v38
bash deploy.sh
```

What-if ska nu visa **`~ Modify`** på VNet:et, där det nya subnätet läggs till. Allt annat ska vara oförändrat. Svara `j`.

