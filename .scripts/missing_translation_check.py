import os
import re
import sys
import textwrap

import defusedxml.ElementTree as ET


# Step 1: Parse locales.xml to extract Lua file names
def parse_locales_xml(xml_file):
    tree = ET.parse(xml_file)
    root = tree.getroot()
    namespace = {"ns": root.tag.split("}")[0].strip("{")}
    locale_files = [
        script.attrib["file"] for script in root.findall("ns:Script", namespace)
    ]
    return locale_files


# Step 2: Load and parse a Lua file into a dictionary
def load_lua_file(lua_file):
    result = {}
    with open(lua_file, "r") as file:
        for line in file:
            # Use regex to capture the key and value correctly
            match = re.match(r'L\["(.+)"\]\s*=\s*(true|"[^"]*")', line.strip())
            if match:
                key = match[1]
                value = match[2]
                result[key] = value
    return result


# Step 3: Compare translations
def compare_translations(reference_dict, target_dict, locale):
    missing_keys = []
    extra_keys = []

    # Check for missing keys in the target dictionary
    for key, value in reference_dict.items():
        if key not in target_dict:
            # If the reference value is True, use the key as the value
            enUS_value = key if value.lower() == "true" else value.strip('"')
            missing_keys.append(f"| {key} | {enUS_value} |")

    # Check for extra keys in the target dictionary
    for key in target_dict:
        if key not in reference_dict:
            extra_keys.append(key)

    # Create markdown output for missing keys
    if missing_keys:
        markdown_report = f"# Translation Status for {locale}\n\n"
        markdown_report += f"Translation progress: {(1 - (len(missing_keys) / len(reference_dict))) * 100:.1f}%\n\n"
        markdown_report += f"Missing translations: {len(missing_keys)}\n\n"
        markdown_report += "<details>\n"
        markdown_report += (
            "    <summary>Missing Keys and their enUS values</summary>\n\n"
        )
        markdown_report += "| Missing Key | enUS Value |\n"
        markdown_report += "|-------------|------------|\n"
        markdown_report += "\n".join(missing_keys)
        markdown_report += "\n</details>\n\n"
        markdown_report += f"\n\n_You can even make changes for [this file](https://github.com/Mctalian-WoW-Addons/RPGLootFeed/edit/main/locale/{locale}) and open a PR directly in your browser_\n\n"

        translation_stub = "\n".join(
            [f'L["{key.split("|")[1].strip()}"] = ""' for key in missing_keys]
        )
        details_section = textwrap.dedent(
            f"""

<details>
    <summary>Please provide one or more of these values in a Pull Request or a Comment on this issue</summary>

```
{translation_stub}
```
</details>

"""
        )
        markdown_report += details_section

    else:
        markdown_report = None

    return markdown_report, extra_keys


# Step 4: Main function to load files and perform comparison
def main():
    locale_dir = "RPGLootFeed/locale"
    output_directory = ".scripts/.output"
    ignored_files = ["main.lua"]

    # Create output_directory if it doesn't exist
    if not os.path.exists(output_directory):
        os.makedirs(output_directory)
    else:
        for filename in os.listdir(output_directory):
            file_path = os.path.join(output_directory, filename)
            try:
                os.unlink(file_path)
            except Exception as e:
                print("Failed to delete %s. Reason: %s" % (file_path, e))

    locales_xml = f"{locale_dir}/locales.xml"
    locale_files = parse_locales_xml(locales_xml)

    # Reference locale (enUS.lua)
    reference_file = "enUS.lua"
    reference_dict = load_lua_file(f"{locale_dir}/{reference_file}")

    has_extra_keys = False

    # Compare each locale with the reference
    for locale_file in locale_files:
        if locale_file in ignored_files:
            continue
        if locale_file != reference_file:
            target_dict = load_lua_file(f"{locale_dir}/{locale_file}")
            markdown_report, extra_keys = compare_translations(
                reference_dict, target_dict, locale_file
            )

            if markdown_report:
                # Create output file for missing translations
                output_file_path = os.path.join(
                    output_directory, f"{locale_file}_missing_keys.md"
                )
                with open(output_file_path, "w") as output_file:
                    output_file.write(markdown_report)
                print(f"Missing translations written to {output_file_path}")

            if extra_keys:
                # Print extra keys to console and set flag
                print(f"\n\nERROR: Extra translation keys in {locale_file}:")
                for key in extra_keys:
                    print(f"  {key}")
                has_extra_keys = True

    # Exit with non-zero code if extra keys were found
    if has_extra_keys:
        sys.exit(1)
    else:
        print("No extra translation keys found.")


if __name__ == "__main__":
    main()
