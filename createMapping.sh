#!/bin/bash

# add all utility functions
source ./utils.sh

# Global variables
LOGS_DIR=./Logs
CONFIG_DIR=./Config
MAPPING_DIR=./Mapping
TEMP_FILE=$LOGS_DIR/applicationListTemp.json
OUTPUT_FILE=$MAPPING_DIR/mappingAPP-Product-generated.json


function generateMappingFile() {

    # create the file
    echo "Initialising Mapping file ($OUTPUT_FILE)"
    echo "[]" > $OUTPUT_FILE

    # read Application list from APIM
    getFromApiManager "applications" $TEMP_FILE

    # loop over the result and keep interesting data (name / description / org)
    cat $TEMP_FILE | jq -rc ".[] | {appId: .id, orgId: .organizationId, appName: .name}" | while IFS= read -r line ; do

        #echo "line=$line"
        # read values
        V7_APP_ID=$(echo $line | jq -r '.appId')
        V7_ORG_ID=$(echo $line | jq -r '.orgId')
        V7_APP_NAME=$(echo $line | jq -r '.appName')

        # read organization name for creating the corresponding team name if needed
        v7_ORG_NAME=$(getAPIM_OrganizationName "$V7_ORG_ID")
        echo "  TEAM_NAME=$v7_ORG_NAME / APP_NAME=$V7_APP_NAME" >&2

        # Adding the organization as a team in Amplify?
        if [[ "$v7_ORG_NAME" != "Amplify Agents" ]]; then

            # create the mapping header (APP / owner)
            # Add  
            echo "  Create Application ($V7_APP_NAME) mapping section..."
            jq -n -f ./jq/mapping-template.jq --arg applicationName "$V7_APP_NAME" --arg owningTeam "$v7_ORG_NAME" > $MAPPING_DIR/mapping-app.json

            # for each application, find the API.
            getFromApiManager "applications/$V7_APP_ID/apis" "$LOGS_DIR/app-$V7_APP_ID-apis.json" > $LOGS_DIR/app-api-$V7_APP_ID-list.json

            # for each API, find the product and plan that match it
            cat $LOGS_DIR/app-$V7_APP_ID-apis.json | jq -rc ".[] | {apiId: .apiId}" | while IFS= read -r appApiLine ; do

                V7_API_ID=$(echo $appApiLine | jq -r '.apiId')
                V7_API_NAME=$(getAPIM_APIName "$V7_API_ID")

                # search product
                PRODUCT_NAME="TBD"

                # search product plan
                PRODUCT_PLAN_NAME="TBD"

                # search environement hosting the API
                EMVIRONMENT_NAME="TBD"
            
                # create the mapping-api piece
                echo "      create mapping-API for API ($V7_API_NAME)" 
                jq -n -f ./jq/mapping-template-api.jq --arg apiName "$V7_API_NAME" --arg productName "$PRODUCT_NAME" --arg productPlanName "$PRODUCT_PLAN_NAME" --arg environment "$EMVIRONMENT_NAME" > $MAPPING_DIR/mapping-api.json

                # add it to the Mapping array
                echo "      add current into application mapping array"
                jq --slurpfile file2 $MAPPING_DIR/mapping-api.json '(.Mapping += $file2)' $MAPPING_DIR/mapping-app.json > $MAPPING_DIR/mapping-app-temp.json
                mv $MAPPING_DIR/mapping-app-temp.json $MAPPING_DIR/mapping-app.json
            done

            # add current Application mapping into the target file
            echo "  Adding application mapping section into the output generated file"
            jq --slurpfile file2 $MAPPING_DIR/mapping-app.json '(. += $file2)' $OUTPUT_FILE > $MAPPING_DIR/tempFile.json
            mv $MAPPING_DIR/tempFile.json $OUTPUT_FILE

            # clean intermediate files
            rm -rf $MAPPING_DIR/mapping-app.json
            rm -rf $MAPPING_DIR/mapping-api.json
        fi

    done

}


#########
# Main
#########

echo ""
echo "==============================================================================" 
echo "== Creating API/APP mapping file fron API Manager and Central               ==" 
echo "== API Manager access and Amplify Platform access are required              =="
echo "== curl and jq programs are required                                        =="
echo "==============================================================================" 
echo ""

if [[ $1 != null ]]
then
    source $1

    if [[ $MAPPING_FILE_NAME != null ]]
    then
        OUTPUT_FILE=$MAPPING_DIR/$MAPPING_FILE_NAME
        echo "Set sepecific output Mapping file: $OUTPUT_FILE"
    fi
else
    echo "We are using the default env.properties"
    source $CONFIG_DIR/env.properties
fi

echo "Checking pre-requisites (axway CLI, curl and jq)"
# check that axway CLI is installed
if ! command -v axway &> /dev/null
then
    echo "axway CLI could not be found. Please be sure you can run axway CLI on this machine"
    exit 1
fi

#check that curl is installed
if ! command -v curl &> /dev/null
then
    echo "curl could not be found. Please be sure you can run curl command on this machine"
    exit 1
fi

#check that jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found. Please be sure you can run jq command on this machine"
    exit 1
fi
echo "All pre-requisites are available" 

#login to the platform
loginToPlatform

echo ""
echo "Creating the Mapping file"
generateMappingFile
echo "Done."

#rm $LOGS_DIR

exit 0