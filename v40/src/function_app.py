import json
import logging
import os
import uuid
from datetime import datetime, timezone
from html import escape

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, ContentSettings

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

_blob_service = None


def blob_service():
    """Skapar klienten första gången och återanvänder den sedan.
    DefaultAzureCredential hämtar token via appens hanterade identitet."""
    global _blob_service
    if _blob_service is None:
        _blob_service = BlobServiceClient(
            account_url=os.environ["STORAGE_ACCOUNT_URL"],
            credential=DefaultAzureCredential(),
        )
    return _blob_service


def las_falt(req):
    """Läser fälten från ett vanligt formulär eller från JSON."""
    if req.form:
        return {k: req.form.get(k, "").strip() for k in ("name", "mail", "message")}
    try:
        data = req.get_json()
    except ValueError:
        data = {}
    return {k: str(data.get(k, "")).strip() for k in ("name", "mail", "message")}


@app.route(route="arende", methods=["POST"])
def arende_mottagning(req: func.HttpRequest) -> func.HttpResponse:
    falt = las_falt(req)
    if not all(falt.values()):
        return func.HttpResponse("Fälten name, mail och message krävs.", status_code=400)

    nu = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    arende_id = f"{nu}-{uuid.uuid4().hex[:8]}"
    arende = {"id": arende_id, **falt, "created": nu, "kalla": "azure-function"}

    container = os.environ.get("ARENDE_CONTAINER", "arenden")
    blob = blob_service().get_blob_client(container, f"{arende_id}/arende.json")
    blob.upload_blob(
        json.dumps(arende, ensure_ascii=False),
        content_settings=ContentSettings(content_type="application/json"),
    )
    logging.info("Ärende %s sparat i %s", arende_id, container)

    if req.form:
        html = (f"<h1>Tack {escape(falt['name'])}!</h1>"
                f"<p>Ditt ärende har registrerats med id {arende_id}.</p>")
        return func.HttpResponse(html, mimetype="text/html", status_code=200)

    return func.HttpResponse(
        json.dumps({"status": "mottaget", "id": arende_id}),
        mimetype="application/json",
        status_code=201,
    )
