# SDK Generation
This program generates the Bazel targets required for rules_dotnet to work with the upstream .Net SDK.

It does the following:

1. Updates the available .Net SDK versions so that the end user of rules_dotnet can choose the SDK version they want to use.
2. Updates the avilable runtime identifiers (RIDs) so that the end user of rules_dotnet can choose the RID they want to when publishing.
3. Updates and creates the Bazel targest for the targeting/runtime/apphost packs that are fetched by rules_dotnet when building.

## Usage

To run the program simply run the `update-sdk.sh` script

# References
* https://github.com/dotnet/designs/blob/main/accepted/2019/targeting-packs-and-runtime-packs.md
* https://github.com/dotnet/designs/blob/main/accepted/2020/targeting-packs/targeting-packs.md

