"""
This script will visit https://www.wowhead.com/currencies/hidden and look in the browser's Session Storage
for URLs of the hidden currencies. The output will be formatted as a LUA table with the currency IDs as keys
and "true" as values. The URL will be included as a comment on the line for reference. The currency ID keys
will be sorted in descending order so the highest IDs (i.e. likely most current/recent) are at the top.
"""

import json
import sys
from dataclasses import dataclass
from typing import Dict, List

from playwright.sync_api import sync_playwright


@dataclass
class SessionStorageEntry:
    hash: str
    path: str
    urls: List[str]
    when: int


@dataclass
class HiddenCurrency:
    currency_id: int
    url: str
    value: bool


ignored_currencies = [
    3278,
    2795,
    2794,
    2793,
    2792,
    2791,
    2790,
    2789,
    2788,
    2787,
    2786,
    2785,
]


def get_hidden_currencies() -> Dict[int, HiddenCurrency]:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(ignore_https_errors=True)
        page.goto(
            "https://www.wowhead.com/currencies/hidden",
            wait_until="domcontentloaded",
            timeout=15000,
        )

        # Check if we hit the CDN error page
        if "error-static-cdn" in page.url:
            raise RuntimeError(
                f"Wowhead CDN is blocked. Page redirected to: {page.url}\n"
                f"The firewall/proxy needs to allow access to Wowhead's CDN domains."
            )

        # Wait for the specific data we need in session storage
        page.wait_for_function(
            "window.sessionStorage.getItem('wh.dataEnv:1.listview.browse') !== null",
            timeout=10000,
        )

        # Extract the session storage data
        raw_session_data = page.evaluate(
            "window.sessionStorage.getItem('wh.dataEnv:1.listview.browse')"
        )
        browser.close()

        # Parse the JSON data
        raw_data = json.loads(raw_session_data)
        session_data = [SessionStorageEntry(**item) for item in raw_data]

        hidden_currency_entry = next(
            (entry for entry in session_data if entry.path == "/currencies/hidden"),
            None,
        )
        if hidden_currency_entry is None:
            raise ValueError("Could not find hidden currency data in session storage")

        # Extract the currency IDs from the URLs
        hidden_currency_urls = hidden_currency_entry.urls

        hidden_currencies: Dict[str, HiddenCurrency] = {}
        for url in hidden_currency_urls:
            currency_id_start = url.split("=")[1]
            currency_id = int(currency_id_start.split("/")[0])
            value = True
            if currency_id in ignored_currencies:
                value = False
            hidden_currencies[currency_id] = HiddenCurrency(
                currency_id=currency_id, url=url, value=value
            )

        return hidden_currencies


if __name__ == "__main__":
    lua_filepath = sys.argv[1] if len(sys.argv) > 1 else None
    hidden_currencies = get_hidden_currencies()

    lua_contents = "G_RLF.hiddenCurrencies = {\n"
    for currency_id in sorted(hidden_currencies.keys(), reverse=True):
        url = hidden_currencies[currency_id].url
        value = "true" if hidden_currencies[currency_id].value else "false"
        lua_contents += f"\t[{currency_id}] = {value}, -- https://wowhead.com{url}\n"
    lua_contents += "}\n"

    if lua_filepath:
        contents = ""
        with open(lua_filepath, "r") as f:
            contents = f.read()

        # Remove contents between -- START_GENERATED_CONTENT and -- END_GENERATED_CONTENT
        start_marker = "-- START_GENERATED_CONTENT\n"
        end_marker = "-- END_GENERATED_CONTENT\n"
        start_index = contents.find(start_marker)
        end_index = contents.find(end_marker)
        if start_index != -1 and end_index != -1:
            contents = (
                contents[: start_index + len(start_marker)]
                + lua_contents
                + contents[end_index:]
            )

        with open(lua_filepath, "w") as f:
            f.write(contents)
    else:
        print(lua_contents)

    sys.exit(0)
