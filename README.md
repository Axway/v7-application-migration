# Axway API Manager Application Migration

Tool for migrating Axway API Manager applications into Marketplace applications
This document describes all the steps necessary to migrate your Axway API Manager Applications to the Amplify Enterprise Marketplace.
The migration from Axway API Manager to the Enterprise Marketplace, consists of the following steps:

1. Create the mapping between Axway API Manager proxies and Marketplace product & plans
2. Migrate the applications (one or all) using the previous mapping

The script needs to be run in a machine where Axway API MAnager and Amplify Entreprise Marketplace are accessible via their respective APIs.

But before you start with the migration, we recommend you get yourself familiarized with the Amplify Enterprise Marketplace.
Please take a moment to watch our Enterprise Marketplace intro tutorial at <https://university.axway.com/learn/courses/11665/introduction-to-amplify-enterprise-marketplace>. You can also access our documentation at <https://docs.axway.com/bundle/amplify-central/page/docs/index.html>.

## Pre-requisits

* [Axway CLI](https://docs.axway.com/bundle/amplify-central/page/docs/integrate_with_central/cli_central/index.html)
* [jq](https://jqlang.github.io/jq/)
* [curl](https://curl.se/)
* Access to API Manager APIs endpoint
* Access to Amplify Entreprise Marketplace APIs

## Concepts

### Marketplace consumer team

We took the postulat to map any Axway API Manager Organization to a Amplify Platform team (the Axway API Manager organization name become the team name in Amplify Platform).
Like this when discovery agent discover APIS, the API owner becomes the team that correlate to the Axway API Manager Organization.

### Marketplace Subscription

The Marketplace subscription is a concept that does not exist in Axway API Manager. The Subscription goal is to monetize your API via a product plan where quotas and pricing are defined. The subscription belongs to a team where all individuals part of the team could use it for their own needs.

### Marketplace Application

The Marketplace application is similar to the Axway API Manager. It has a owner and provide access to API via some credentials

#### Marketplace Access request

The Marketplace Access request defines which Application can access to which product API under a specific subscription. This relates to the Application/Api links in Axway API Manager.

#### Marketplace Credentials

The Marketplace credentials are similar to Axway API Manager credentials (API key, Oauth).

### Objects correspondance

The following table shows the mapping between Axway API Manager Application and Enterprise Marketplace objects:

| Initial Objects                      | Marketplace subscription | Marketplace application | Marketplace Access request | Marketplace credential |
|--------------------------------------|--------------------------|-------------------------|----------------------------|------------------------|
|                                      |                          |                         |                            |                        |
| **API MAnager Application**          |                          |                         |                            |                        |
|  Name                                |                          | Title                   | Tile=Name-ApiName          | Generated title        |
|  Description                         |                          | Description             |                            |                        |
|  icon                                |                          | Icon                    |                            |                        |
|  Organization name                   | Owning team name         | Owning team name        | Owning team name           | Owning team name       |
|  Access Api names                    |                          |                         | APIService name            |                        |
|  Credential API KEY                  |                          |                         |                            | Name + hash            |
|  Credential OAUTH - CLIENT ID        |                          |                         |                            | Name + hash            |
|  Credential EXTERNAL - CLIENT ID     |                          |                         |                            | Name + hash            |
|                                      |                          |                         |                            |                        |
| **Mapping file**                     |                          |                         |                            |                        |
|  Product name                        | Product ID               |                         | Product ID                 |                        |
|                                      |                          |                         | Product version ID         |                        |
|  Plan name                           | Plan ID                  |                         |                            |                        |
|  CredentialRequestDefinition         |                          |                         |                            | CRD_ID                 |

## Migration steps

1. create the environment properties file
2. create and validate the mapping file
3. stop the Discovery and Traceability agents running in the environment
4. run the application migration script
5. re-start the Discovery and Traceability agents running in the environment

### Step 1 - create the environment properties file

This file located in config directory contains:

* properties to connect to Amplify Platform using a service account: `CLIENT_ID` and `CLIENT_SECRET`
* properties to connect to Axway API Manager: `APIMANAGER_*`
* Marketplace url
* property to define which mapping file to use

You can update the default file or make a copy of it so that you can rename it appropriately with a meaningful name.

### Step 2 - Create and validate the mapping file

Since it is impossible to guess what the Axway API Manager Application should be linked to, we defined a mapping file for each APP/API to map to a product and plan in the Marketplace so that the migration will be able to create the correct Marketplace subscription.

We also need a owning team for subscription. For that 2 choices, either we used the organization where the APP belongs or user will surcharge the value when validating the mapping file.

This mapping is summarized as follows:

For each application, we have the owning team (could be empty and the migration will use the Organization name where the APP leaves) and the mapping for each API that the Application can access:

```json
{
    "ApplicationName": "v7 APPLICATION NAME 1",
    "owningConsumerTeam": "TEAM WHO IS OWNING THE SUBSCRIPTION",
    "Mapping": [
        {
            "apiName": "v7 API NAME 1",
            "productName": "MARKETPLACE PRODUCT NAME",
            "planName": "MARKETPLACE PRODUCT PLAN NAME",
            "environment": "CENTRAL ENVIRONMENT WHERE API HAS BEEN DISCOVERED",
            "credentialRequestDefinitionId": "CRD ID for MKT - coming from AssetResources.CRD"
        },
        {
            "apiName": "v7 API NAME 2",
            "productName": "",
            "planName": "MARKETPLACE PRODUCT PLAN NAME",
            "environment": "CENTRAL ENVIRONMENT WHERE API HAS BEEN DISCOVERED",
            "credentialRequestDefinitionId": "CRD ID for MKT - coming from AssetResources.CRD"
        }
    ],
}
```

For creating the mapping file, run the `createMapping.sh` script.

Be default the script uses `env.properties` from the Config directory but you can pass the file name as an argument to the script: `createMapping.sh ./Config/envLbean018.properties`

The output file is defaulted to: `./Mapping/mappingAPP-product-generated.json`. And can be changed in the properties file directly.

The script ignore all application present in the Amplify Agent organization as those one are already managed by the Discovery Agent.

Once the mapping file is generated, it is highly recommended to review its content to ensure the found product and product plan are the one to use for the subscription. If something does not match, it may result in error in the migration script.

During the mapping creation, it is possible to receive **Warning** message:

1. API (`V7_API_NAME`) not found. Please check that Discovery Agent has discovered API (`V7_API_NAME`)
2. API (`V7_API_NAME`) has been found multiple times. Please remove any duplicate prior to proceed. to keep only one version.
3. API (`V7_API_NAME`) does not contain the correct API Manager API ID. Either the API has not been discovered or the agent is too old.
4. No asset is managing `V7_API_NAME`... You need to have at least one asset/product/plan to run the migration.
5. API (`V7_API_NAME`) is embedded in multiple assets. Mapping file not updated
6. API (`V7_API_NAME`) is part of an asset (`ASSET_NAME`) that is not embed in any product.
7. API (`V7_API_NAME`) is part of an asset (`ASSET_NAME`) that is embed in multiple products.
8. API (`V7_API_NAME`) is part of a product (`PRODUCT_NAME_FOUND`) that has no plan.
9. API (`V7_API_NAME`) is part of a product (`PRODUCT_NAME_FOUND`) that have multiple plans.
10. API (`V7_API_NAME`) is not part of any plan quota of the product (`PRODUCT_NAME_FOUND`).

For all these warning, `TBD` will be added in the mapping file under `productName` or `planName` or `environment` or `credentialRequestDefinitionId` variable. If you choose to ignore those warning, the migration for the specific application will not be complete.

NOTE for credentialRequestDefinition:



### Step 3 - stop the Discovery and Traceability agents running in the environment

In order to avoid the agent from provisioning the application that will be migrated, you should stop the Discovery and Traceability agents.

Refer to the Agent stop command based on you current deployment (executable / Docker / Helm)

### Step 4 - run the application migration script

Run the `createMarketplaceApplicationFromV7App.sh` script

Be default the script uses env.properties from the Config directory but you can pass the file name as an argument to the script: `createMarketplaceApplicationFromV7App.sh ./Config/envLbean018.properties`

Also it is possible to run the script for only 1 application instead of all applications.

The script ignore all application present in the Amplify Agent organization

Once the script find an application that needs to be migrated (not part of the Amplify Agent organization already), it performs the following:

* create an Amplify team using the organization name of the Api Manager application if this team does not exist
* create the Marketplace application if it does not exists yet or reused the existing one
* create the Marketplace subscription using the information from the mapping file
* approve the subscription (if subscription approval is manually set)
* for each API accessible from the Application:
  * create the Marketplace access request
    * approve the access request (if access request is manually approved)
    * set the access request as provisioned
* for each credential type available in the application:
  * create the Marketplace credential
  * add the hashing value the discovery agent would put on the credentials
  * set the credentials as provisioned
* **Update the V7 app name** using the Marketplace Application logical name (internal name not visible to the Marketplace users) so that Traceability Agent will be able to correctly correlate the traffic to the appropriate Marketplace subscription/application.

### Step 5 - re-start the Discovery and Traceability agents running in the environment

Once the migration is finished, you have to delete the agent cache directory for each agent. This will force the agent to read the new access request and credentials to update its cache once it restart.

Restart the agents

Refer to the Agent start command based on you current deployment (executable / Docker / Helm)
