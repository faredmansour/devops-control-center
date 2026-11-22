"""Result delivery to the DCC control plane."""
import json
from urllib.error import URLError
from urllib.request import Request, urlopen


def post_result(callback_url: str, callback_token: str, payload: dict) -> None:
    request = Request(
        callback_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-DCC-Result-Token": callback_token,
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=10) as response:
            if response.status not in {200, 202}:
                raise RuntimeError("The DCC result callback was rejected.")
    except (URLError, TimeoutError, ValueError) as error:
        raise RuntimeError("The DCC result callback could not be delivered.") from error
