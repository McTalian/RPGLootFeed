import json
import re
import sys


def check_print_statements(file_path):
    violations = []

    with open(file_path, "r") as file:
        lines = file.readlines()

    for line_number, line in enumerate(lines, start=1):
        # Strip leading and trailing whitespaces for proper comparison
        stripped_line = line.strip()

        # Ignore lines that start with a Lua comment
        if stripped_line.startswith("--"):
            continue

        match = re.search(r"\bprint\b", line)
        if match:
            column_number = match.start() + 1
            if not re.search(r"\bself:Print\b|\bG_RLF:Print\b", line):
                violations.append(
                    {
                        "ruleId": "invalid-print",
                        "message": {
                            "text": "Invalid `print`, use `self:Print(...)` or `G_RLF:Print(...)`"
                        },
                        "locations": [
                            {
                                "physicalLocation": {
                                    "artifactLocation": {"uri": file_path},
                                    "region": {
                                        "startLine": line_number,
                                        "startColumn": column_number,
                                    },
                                }
                            }
                        ],
                    }
                )

    return violations


def generate_sarif(violations):
    sarif_output = {
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "Invalid Print",
                        "rules": [
                            {
                                "id": "invalid-print",
                                "shortDescription": {
                                    "text": "Disallowed `print` statements"
                                },
                                "fullDescription": {
                                    "text": "Lua files should not contain `print` statements that are not `self:Print(...)` or `G_RLF:Print(...)`."
                                },
                            }
                        ],
                    }
                },
                "results": violations,
            }
        ],
    }
    return sarif_output


def main():
    if len(sys.argv) != 2:
        print("Usage: check_for_invalid_prints.py <file_path>")
        sys.exit(1)

    file_path = sys.argv[1]
    violations = check_print_statements(file_path)
    sarif_output = generate_sarif(violations)

    print(json.dumps(sarif_output, indent=2))


if __name__ == "__main__":
    main()
