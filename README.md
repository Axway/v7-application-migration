# Axway API Manager application migration to Marketplace applications

This document describes all the steps necessary to migrate your Axway API Manager Applications to the Amplify Enterprise Marketplace.
The migration from Axway API Manager to the Enterprise Marketplace, consists of the following steps:

1. Create the mapping between Axway API Manager proxies and Marketplace product & plans
2. Migrate the applications (one or all) using the previous mapping

The script needs to be run in a machine where Axway API Manager and Amplify Enterprise Marketplace are accessible via their respective APIs.

But before you start with the migration, we recommend you get yourself familiarized with the Amplify Enterprise Marketplace.
Please take a moment to watch our Enterprise Marketplace intro tutorial at <https://university.axway.com/learn/courses/11665/introduction-to-amplify-enterprise-marketplace>. You can also access our documentation at <https://docs.axway.com/bundle/amplify-central/page/docs/index.html>.

## Pre-requisites

* [Axway CLI](https://docs.axway.com/bundle/amplify-central/page/docs/integrate_with_central/cli_central/index.html)
* [jq](https://jqlang.github.io/jq/)
* [curl](https://curl.se/)
* Access to API Manager APIs endpoint
* Access to Amplify Entreprise Marketplace APIs
* **Some products and product plans created on top of the discovered APIs.**

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

| Initial Objects                      | Marketplace subscription | Marketplace application | Marketplace Access request | Marketplace credential   |
|--------------------------------------|--------------------------|-------------------------|----------------------------|--------------------------|
|                                      |                          |                         |                            |                          |
| **API MAnager Application**          |                          |                         |                            |                          |
|  Name                                |                          | Title                   | Tile=Name-ApiName          | Generated title          |
|  Description                         |                          | Description             |                            |                          |
|  icon                                |                          | Icon                    |                            |                          |
|  Organization name                   | Owning team name         | Owning team name        | Owning team name           | Owning team name         |
|  Access Api names                    |                          |                         | APIService name            |                          |
|  Credential API KEY                  |                          |                         |                            | Name + crypted value     |
|  Credential OAUTH - CLIENT ID        |                          |                         |                            | Name + crypted secret    |
|  Credential EXTERNAL - CLIENT ID     |                          |                         |                            | Name + no crypted secret |
|                                      |                          |                         |                            |                          |
| **Mapping file**                     |                          |                         |                            |                          |
|  Product name                        | Product ID               |                         | Product ID                 |                          |
|                                      |                          |                         | Product version ID         |                          |
|  Plan name                           | Plan ID                  |                         |                            |                          |
|  CredentialRequestDefinition         |                          |                         |                            | CRD_ID                   |

Note regarding Credentials:

* After the migration, consumer will be able to see his credential secret (API Key or oauth credential secret) for 3 days in the Marketplace.
* For **External credential**, no value will be provided as the secret is not store in the v7 application but on the IDP. Consumer will have to contact the provider to get his secret if he lost it or request a new one.
* For **Oauth credential**, there are 2 definitions (`oauth-client-id-secret` and `oauth-client-id-private-key`) ; the mapping script will add both in the credentialRequestDefinition field but the application migration script can work with only one at a time, thus update the mapping file to remove one of them. For that you can search for `\n` in the generated mapping file.
* **HTTP Basic** credentials are not handled.
* Expiration policy: if the environment is setup to handle credential expiration policy, the script can automatically add it to the credentials. For that use the option `ADD_CREDENTIAL_EXPIRATION_POLICY=1` from the **env.properties** file. By default this configuration is not activated

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
    "credentialSuffix": "",
    "Mapping": [
        {
            "apiName": "v7 API NAME 1",
            "apiVersion": "v7 API VERSION",
            "productName": "MARKETPLACE PRODUCT NAME",
            "planName": "MARKETPLACE PRODUCT PLAN NAME",
            "environment": "CENTRAL ENVIRONMENT WHERE API HAS BEEN DISCOVERED",
            "apiServiceInstanceId": "API SERVICE INSTANCE ID",
            "credentialRequestDefinitionId": "CRD ID for MKT - coming from AssetResources.CRD"
        },
        {
            "apiName": "v7 API NAME 2",
            "apiVersion": "v7 API VERSION",
            "productName": "",
            "planName": "MARKETPLACE PRODUCT PLAN NAME",
            "environment": "CENTRAL ENVIRONMENT WHERE API HAS BEEN DISCOVERED",
            "apiServiceInstanceId": "API SERVICE INSTANCE ID",
            "credentialRequestDefinitionId": "CRD ID for MKT - coming from AssetResources.CRD"
        }
    ],
}
```

For creating the mapping file, run the `createMapping.sh` script.

Be default the script uses `env.properties` from the Config directory but you can pass the file name as an argument to the script: `createMapping.sh ./Config/envLbean018.properties`

The output file is defaulted to: `./Mapping/mappingAPP-product-generated.json`. And can be changed in the properties file directly.

The script ignore all applications present in the Amplify Agent organization as those one are already managed by the Discovery Agent.

Once the mapping file is generated, it is highly recommended to review its content to ensure the found product and product plan are the one to use for the Marketplace subscription. If something does not match, it may result in error in the migration script and the field may contains `TBD` which mean the script was not able to determine the value.

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

For all these warning, `TBD` will be added in the mapping file under `productName` or `planName` or `environment` or `apiServiceInstanceId` or `credentialRequestDefinitionId` variable. If you choose to ignore those warning, the migration for the specific application will not be complete.

NOTE for credentialRequestDefinition:

In order to find the appropriate CredentialRequestDefinition used for credential creation in the Marketplace, you need to:

1. find the api service instance corresponding to a service: `axway central get apisi -q metadata.references.name=={api-service-logical-name} -o json | jq -rc '.[].name'`
2. find the CredentialRequestDefinition Id from the asset resource that managed this service instance: `axway central get assetresource -q metadata.references.name=={api-service-instance-name-find-in-step-1} -o json | jq -rc '.[].metadata.references[] | select(.kind == "CredentialRequestDefinition").id'`

It is possible that the above command returns more than one result but the result should be identical as the service has a unique security.

### Step 3 - stop the Discovery and Traceability agents running in the environment

In order to avoid the agent from provisioning the application that will be migrated, you should stop the Discovery and Traceability agents.

Refer to the Agent stop command based on you current deployment (executable / Docker / Helm)

### Step 4 - run the application migration script

Run the `createMarketplaceApplicationFromV7App.sh` script

Be default the script uses env.properties from the Config directory but you can pass the file name as an argument to the script: `createMarketplaceApplicationFromV7App.sh ./Config/envLbean018.properties`

Also it is possible to run the script for only 1 application instead of all applications. For that, add the `APP_NAME_TO_MIGRATE` variable in your configuration file. Sample:

```bash
APP_NAME_TO_MIGRATE="My application to migrate"
```

The script ignore all application present in the Amplify Agent organization

Once the script find an application that needs to be migrated (not part of the Amplify Agent organization already), it performs the following:

* create an Amplify team using the organization name of the Api Manager application if this team does not exist
* create the Marketplace application if it does not exists yet or reused the existing one
* create the Marketplace subscription using the information from the mapping file
* approve the subscription (if subscription approval is manually set)
* for each API accessible from the Application that are not retired:
  * create the Marketplace access request
    * approve the access request (if access request is manually approved)
    * set the access request as provisioned
* for each credential type available in the application:
  * create the Marketplace credential
  * add the hashing value the discovery agent would put on the credentials
  * set the credentials as provisioned
* **Update the V7 app name** using the Marketplace Application logical name (internal name not visible to the Marketplace users) so that Traceability Agent will be able to correctly correlate the traffic to the appropriate Marketplace subscription/application.

NOTE for credential creation:

In the mapping file, the *credentialSuffix* is there to help distinguish credential from various environment on the same application.
By default credentials name is built using the following name convention {credentialType}_{COUNTER}_{credentialSuffixValue} with:

* credentialType: "API_KEY" or "OAUTH" or "EXTERNAL"
* COUNTER: a incremental number starting with 0
* credentialSuffixValue: the value of credentialSuffix variable from the mapping file

Possible output:

* APIKEY_0_DEV
* EXTERNAL_0_PROD, EXTERNAL_1_PROD

### Step 5 - re-start the Discovery and Traceability agents running in the environment

Once the migration is finished, you have to delete the agent cache directory for each agent. This will force the agent to read the new access request and credentials to update its cache once it restart.

Restart the agents

Refer to the Agent start command based on you current deployment (executable / Docker / Helm)

## Troubleshooting

Whenever the script crash, it is recommended to stop it manually by pressing `CTRL + C` keys to avoid farther issues.

Once stopped, and the issue understood/corrected, the script can be re-started. It is smart enough to ensure that previous steps have been executed correctly and pursue the migration. For instance, if you are not sure of your mapping, it is possible to leave the TBD values, run the script a first time. Then update the mapping and run the script a second time. Everything done the first time will not be updated again but only the new things will be processed.

### Debugging information

`utils.sh` script contain a variable to output additional information: refer to `DEBUG` variable in `utils.sh` script and set its value to 1: `DEBUG=1`
This will output some information in the following format: `DEBUG- my debugging message`

To add debugging information, use the `logDebug` function as follow: `logDebug "message to show in debug only"`

### What issue can I encounter?

#### Subscription cannot be created

Be aware that for Free plan, each team only have one subscription possible to avoid abusing such plan.

### Known issue - same API used in multiple applications

A single API coming from a product and 1 subscription cannot be accessed by multiple applications because in that case, each individual application will get the full quota of the subscription and consequently the quota can be over used. In that situation several subscriptions would be required but script cannot select which application to use.
