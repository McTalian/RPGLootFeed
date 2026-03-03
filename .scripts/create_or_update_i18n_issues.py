import os

import requests

# Set up necessary constants
GITHUB_API_URL = "https://api.github.com"
REPO_OWNER = "McTalian-WoW-Addons"
REPO_NAME = "RPGLootFeed"
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")

# GitHub API headers
headers = {
    "Authorization": f"Bearer {GITHUB_TOKEN}",
    "Accept": "application/vnd.github.v3+json",
}

DEFAULT_GET_TIMEOUT = 10
DEFAULT_PATCH_TIMEOUT = 10


def get_all_translation_issues():
    """Search for an existing issue for the given locale."""
    search_url = f"{GITHUB_API_URL}/search/issues"
    query = f"repo:{REPO_OWNER}/{REPO_NAME} is:issue label:i18n state:open"
    params = {"q": query}

    response = requests.get(
        search_url, headers=headers, params=params, timeout=DEFAULT_GET_TIMEOUT
    )
    response.raise_for_status()
    issues = response.json().get("items", [])

    # Create a dictionary with locale as the key and the issue as the value
    issues_dict = {}
    for issue in issues:
        title = issue["title"]
        # Strip the 'i18n: ' prefix and ' Translations' suffix to extract the locale
        if title.startswith("i18n: ") and title.endswith(" Translations"):
            locale = title[len("i18n: ") : -len(" Translations")]
            issues_dict[locale] = issue

    return issues_dict


def create_issue(locale, markdown_content):
    """Create a new GitHub issue with the given locale and content."""
    issue_url = f"{GITHUB_API_URL}/repos/{REPO_OWNER}/{REPO_NAME}/issues"
    title = f"i18n: {locale} Translations"
    issue_data = {
        "title": title,
        "body": markdown_content,
        "labels": ["i18n"],
    }

    response = requests.post(
        issue_url, headers=headers, json=issue_data, timeout=DEFAULT_GET_TIMEOUT
    )
    response.raise_for_status()
    print(f"Issue created: {response.json().get('html_url')}")


def update_issue(issue_number, markdown_content):
    """Update an existing GitHub issue with the new markdown content."""
    issue_url = f"{GITHUB_API_URL}/repos/{REPO_OWNER}/{REPO_NAME}/issues/{issue_number}"
    issue_data = {
        "body": markdown_content,
    }

    response = requests.patch(
        issue_url, headers=headers, json=issue_data, timeout=DEFAULT_PATCH_TIMEOUT
    )
    response.raise_for_status()
    print(f"Issue updated: {response.json().get('html_url')}")


def process_markdown_files(output_directory):
    """Process each markdown file and create or update the corresponding GitHub issue."""
    issues_dict = get_all_translation_issues()

    for filename in os.listdir(output_directory):
        if filename.endswith("_missing_keys.md"):
            locale = filename.split(".")[0]
            with open(os.path.join(output_directory, filename), "r") as file:
                markdown_content = file.read()

            # Check for an existing issue
            existing_issue = issues_dict.get(locale)
            if existing_issue:
                # Update the existing issue
                update_issue(existing_issue["number"], markdown_content)
            else:
                # Create a new issue
                create_issue(locale, markdown_content)


if __name__ == "__main__":
    output_directory = ".scripts/.output"
    process_markdown_files(output_directory)
