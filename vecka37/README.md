# Uppgift 4: Lagring (v37)

Ärendeformuläret sparar till Blob Storage med en hanterad identitet.

**Adrian Forgo Ahlborg** · Microsoft Azure (MOV25), vecka 37 · Novatrix AB · 15 september 2026

---

## Innehåll

1. [Sammanfattning](#1-sammanfattning)
2. [Miljö](#2-miljö)
3. [Lagringskonto och container](#3-lagringskonto-och-container)
4. [Identitet och behörighet](#4-identitet-och-behörighet)
5. [Ändringar i koden](#5-ändringar-i-koden)
6. [Driftsättning](#6-driftsättning)
7. [Arkitektur](#7-arkitektur)
8. [Test](#8-test)
9. [Lärdomar](#9-lärdomar)

---

## 1. Sammanfattning

Den här veckan har jag gjort ärendeformuläret på Novatrix webbsida funktionellt. Webbservern från v36 används fortfarande, men formulärsidan är ersatt med en ny version som skickar till backenden. När någon skickar in ett ärende sparas det nu i containern `arenden` i ett lagringskonto. Det är en liten Flask-backend på servern som gör skrivningen, och den loggar in med den hanterade identiteten jag skapade i v35. Det finns alltså ingen nyckel eller anslutningssträng i koden.

Arbetet bestod i korthet av att skapa lagringskontot och containern, koppla identiteten till VM:en, ge identiteten rätt roll, anpassa koden, driftsätta den och till sist testa att ett ärende faktiskt hamnar i lagringen.

## 2. Miljö

| Objekt | Värde |
|---|---|
| Resursgrupp | RG-novatrix |
| Lagringskonto | stnovatrixmov25 |
| Container | arenden (privat åtkomst) |
| Prestanda / replikering | Standard, LRS |
| Åtkomstnivå | Frekvent (Hot) |
| Virtuell maskin | VM-Novatrix-Web-02-vecka-36-ny |
| Publik IP | 74.241.168.58 |
| Hanterad identitet | ID-Novatrix-App (användartilldelad) |
| Klient-ID | 9f47f1fb-9568-472c-b0ca-e2f52bdbe985 |
| Region | Sweden Central |

Allt bygger vidare på det jag gjort v34 till v36. Servern ligger kvar i `snet-public`, nätverk och brandväggsregler är oförändrade och RBAC-rollerna från v35 gäller fortfarande eftersom de sitter på resursgruppen.

## 3. Lagringskonto och container

![Lagringskontot innan det skapas](vecka37/bilder/bilder/01-lagringskonto.png)
*Bild 1. Lagringskontot innan det skapas.*

![Containern arenden](bilder/02-container.png)
*Bild 2. Containern arenden med anonym åtkomstnivå Privat.*

### Varför Blob Storage

Ett ärende skrivs en gång, läses senare och ändras inte. Det passar Blob Storage bra. Jag funderade på Azure Files, men det är mer tänkt för när flera maskiner ska dela filer som en nätverksdisk, och det behövs inte här.

### Inställningar

Jag valde Standard eftersom ett formulär inte behöver den låga latensen som Premium ger, och Standard är mycket billigare. För redundans valde jag LRS, som har tre kopior i samma datacenter. ZRS eller GRS skyddar bättre men kostar mer, och i en kursmiljö tycker jag inte att det är värt det.

Åtkomstnivån är Frekvent (Hot) eftersom kundtjänst läser ett nytt ärende ganska direkt. Om det här skulle användas på riktigt skulle jag lägga till en livscykelregel som flyttar ärenden äldre än 30 dagar till Låg frekvens.

## 4. Identitet och behörighet

I v35 skapade jag ID-Novatrix-App men gav den inga rättigheter. Nu var det dags att använda den. Jag behövde göra två saker:

1. Koppla identiteten till VM:en. Annars kan servern inte hämta någon token för identiteten.
2. Ge identiteten en roll på containern. Annars får servern en token, men den ger ingen åtkomst.

![Identiteten kopplad till VM:en](bilder/03-identitet-vm.png)
*Bild 3. id-novatrix-app under Användartilldelad på VM:en.*

### Rolltilldelning

Identiteten fick rollen Storage Blob Data-deltagare med omfånget satt på containern:

```text
.../storageAccounts/stnovatrixmov25/blobServices/default/containers/arenden
```

Jag lade rollen på containern och inte på hela lagringskontot. Då kommer identiteten bara åt `arenden` och inga andra containrar. I portalen ser tilldelningen nästan likadan ut oavsett, så det är lätt att råka ge för bred behörighet.

Jag valde bort Storage Blob Data Owner eftersom appen inte behöver kunna ändra behörigheter. Contributor på kontot valde jag också bort, eftersom den rollen kan läsa ut kontonycklarna, och då skulle man ju kunna gå runt identiteten.

![Rolltilldelningen](bilder/04-rolltilldelning.png)
*Bild 4. Rolltilldelningen, omfånget slutar på /containers/arenden.*

![Identitetens översikt](bilder/05-identitet-oversikt.png)
*Bild 5. Översikt över identiteten med klient-ID och objekt-ID.*

## 5. Ändringar i koden

Backenden är en liten Flask-app (`app.py`) som tar emot formuläret och sparar det i Blob Storage. Grundkoden fungerade nästan som den var, jag behövde bara ändra tre rader för att den skulle passa min miljö.

### Ändring 1: Kontonamnet

Först letade jag upp raden med kontonamnet och bytte värdet till mitt eget lagringskonto från avsnitt 3:

```python
STORAGE_ACCOUNT = "stnovatrixmov25"
```

### Ändring 2: Importraden

Grundkoden importerade `DefaultAzureCredential`. Jag letade upp raden:

```python
from azure.identity import DefaultAzureCredential
```

och bytte den till:

```python
from azure.identity import ManagedIdentityCredential
```

### Ändring 3: Inloggningen

Till sist letade jag upp raden där inloggningen skapas:

```python
_credential = DefaultAzureCredential()
```

och bytte den till följande, med klient-ID:t för ID-Novatrix-App från avsnitt 4:

```python
_credential = ManagedIdentityCredential(client_id="9f47f1fb-9568-472c-b0ca-e2f52bdbe985")
```

Anledningen till ändring 2 och 3 är att `DefaultAzureCredential` hittar en systemtilldelad identitet av sig själv, men min identitet är användartilldelad. Eftersom en VM kan ha flera användartilldelade identiteter måste koden tala om vilken som ska användas. Klient-ID är ingen hemlighet, det pekar bara ut identiteten. Själva åtkomsten kommer från rolltilldelningen och från att identiteten är kopplad till VM:en.

![app.py i VS Code](bilder/06-app-py.png)
*Bild 6. app.py öppen i VS Code med de tre ändrade raderna synliga.*

### Hur ett ärende sparas

När formuläret skickas skapar backenden ett ärende-id av tidsstämpeln och en slumpad ändelse. Ärendet sparas som `arende.json` i en mapp med samma namn som id:t, och om det finns en bifogad bild hamnar den i samma mapp. Då ligger allt som hör till ett ärende på samma ställe.

```python
ticket_id = "{0}-{1}".format(stamp, uuid.uuid4().hex[:8])

container.upload_blob(
    name="{0}/arende.json".format(ticket_id),
    data=json.dumps(ticket, ensure_ascii=False).encode("utf-8"),
    overwrite=True,
    content_settings=ContentSettings(content_type="application/json"),
)
```

### Formuläret

Formuläret från v34 saknade `action` och `method`, så datan skickades bara tillbaka till samma sida och sparades ingenstans. Jag lade till `action="/submit"` och `method="post"` så att datan skickas till backenden. Jag behövde också `enctype="multipart/form-data"`, annars följer inte bilden med. Det ger inget fel, bilden kommer bara inte fram.

```html
<form action="/submit" method="post" enctype="multipart/form-data">
```

## 6. Driftsättning

Jag redigerade filerna på min egen dator och laddade upp dem till servern. På så sätt är filerna i repot samma som de som körs.

### Installera beroenden på servern

```bash
sudo apt update
sudo apt install -y python3 python3-pip
sudo pip3 install --ignore-installed blinker flask azure-identity azure-storage-blob
sudo mkdir -p /opt/arendeapp
```

> **Tillagt av mig:** `--ignore-installed blinker`

Första gången fick jag fel på paketet blinker. Flask behöver en nyare version än den som följer med Ubuntu, och pip kan inte avinstallera något som apt har installerat. Med `--ignore-installed blinker` gick det igenom.

![Paketinstallationen](bilder/07-pip-install.png)
*Bild 7. Installationen och kontrollen att biblioteken går att importera.*

### Ladda upp filerna

```bash
scp -i VM-novatrix-web_key.pem app.py index.html nginx-arende.conf arendeapp.service azureuser@74.241.168.58:/tmp/
```

![Filerna överförda med scp](bilder/08-scp.png)
*Bild 8. Filerna överförda med scp.*

### Flytta filerna och starta tjänsterna

```bash
sudo mv /tmp/app.py /opt/arendeapp/app.py
sudo mv /tmp/index.html /var/www/html/index.html
sudo mv /tmp/nginx-arende.conf /etc/nginx/sites-available/default
sudo mv /tmp/arendeapp.service /etc/systemd/system/arendeapp.service

sudo chown root:root /opt/arendeapp/app.py /etc/nginx/sites-available/default /etc/systemd/system/arendeapp.service
sudo chown www-data:www-data /var/www/html/index.html

sudo nginx -t
sudo systemctl daemon-reload
sudo systemctl enable --now arendeapp
sudo systemctl restart nginx
```

![nginx -t](bilder/09-nginx-test.png)
*Bild 9. nginx -t visar att konfigurationen är giltig.*

Backenden körs som en systemd-tjänst, så den startar om av sig själv om den kraschar och när VM:en startas om.

![systemctl status](bilder/10-systemctl-status.png)
*Bild 10. arendeapp är igång och lyssnar på 127.0.0.1:5000.*

I bilden syns en varning om att Flask kör en utvecklingsserver. Det räcker för uppgiften, men i skarp drift skulle jag köra appen med till exempel gunicorn istället.

### Brandvägg

Jag behövde inte öppna några nya portar. Backenden lyssnar bara på `127.0.0.1:5000`, alltså inne på servern. nginx tar emot trafiken på port 80 och skickar `/submit` vidare till backenden. Varken NSG-reglerna eller ufw behövde ändras, och backenden går inte att nå utifrån.

## 7. Arkitektur

Flödet när någon skickar in ett ärende:

1. Webbläsaren skickar formuläret med POST till `/submit`.
2. nginx på port 80 skickar vidare anropet till Flask på `127.0.0.1:5000`.
3. Flask hämtar en token via IMDS med ID-Novatrix-App.
4. Flask sparar `arende.json` och bilden i `stnovatrixmov25/arenden/<ärende-id>/`.

Anledningen till att det behövs en backend är att en webbsida i webbläsaren inte har någon identitet i Azure. Om sidan skulle skriva direkt till lagringen måste nyckeln ligga i källkoden, och då kan alla som besöker sidan se den.

## 8. Test

| Test | Resultat | Bild |
|---|---|---|
| Hälsokontroll av backenden | status ok, rätt konto och container | Bild 11 |
| Skicka ärende med bild | Tack-sida med id 20260915T110747Z-20b68635 | Bild 12 |
| Kontrollera lagringen | arende.json och bilden finns under id:t | Bild 13 |

### Hälsokontroll

```bash
curl http://localhost:5000/health
```

```json
{"account":"stnovatrixmov25","container":"arenden","status":"ok"}
```

Svaret visar att backenden är igång och att den har rätt kontonamn och container.

![Hälsokontrollen](bilder/11-halsokontroll.png)
*Bild 11. Hälsokontrollen svarar ok.*

### Skicka in ett ärende

Jag fyllde i formuläret, bifogade en bild och skickade. Tack-sidan visade ärende-id `20260915T110747Z-20b68635`.

![Tack-sidan](bilder/12-tack-sida.png)
*Bild 12. Tack-sidan efter inskickat ärende.*

I containern fanns sedan en mapp med samma id, med `arende.json` (164 B) och `Tt0NmR.jpg` (346,53 KiB). Eftersom id:t är detsamma vet jag att det är just mitt testärende som sparats. Båda filerna har åtkomstnivå Frekvent, som de ärvt från kontot.

![Ärendet i containern](bilder/13-blobbar.png)
*Bild 13. Ärendet och bilden i containern.*

I bild 13 står det att autentiseringsmetoden är Åtkomstnyckel. Det gäller när jag själv tittar i portalen, eftersom jag är Owner och portalen då använder kontonyckeln. Appen använder inte nyckeln utan kommer bara in via identiteten och rollen på containern.

## 9. Lärdomar

- Grundkoden var skriven för en systemtilldelad identitet. Min identitet är användartilldelad, så jag pekar ut den med klient-ID för att koden säkert ska använda den identitet som har rollen på containern.
- Det räcker inte att identiteten finns. Den måste både vara kopplad till VM:en och ha en roll, och rollens omfång spelar stor roll för hur mycket den kommer åt.
- Ett HTML-formulär utan `enctype="multipart/form-data"` skickar inte med filer, och man får inget felmeddelande om det.
