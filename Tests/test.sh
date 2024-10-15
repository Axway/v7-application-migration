#!/bin/bash

# Guillaume repo = https://git-ext.ecd.axway.com/cso-reusable/api-management/amplify-components/-/tree/main/marketplace/migration/engie/app-migration-tool-v2?ref_type=heads

# Sourcing user-provided env properties
#source ../config/envLBEAN018.properties
source ../config/envLBEAN-QA-DEV.properties

# add all utility functions
source ../utils.sh

# Global variables
LOGS_DIR=./logs
TOOL_DIR=../Tools
CONFIG_DIR=../config

testMergeMapping() {

    jq --slurpfile file2 ./File2.json '(.Mapping += $file2)' ./File1.json > ./generated_file-tmp.json
    jq --slurpfile file2 ./File2.json '(.Mapping += $file2)' ./generated_file-tmp.json > ./$LOGS/generated_file.json
    rm ./generated_file-tmp.json
}

testHashingCredential() {
    CRED_HASH=$(hashingCredentialValue "$CREDENTIAL_HASH_2_PARAM" "2abfcd4d-92a9-4b64-b32e-fa945325ada7" "4e0b8030-3feb-4dd4-b98c-6ce60654e9e4")
    echo "Hash for 2 param: $CRED_HASH"
    CRED_HASH=$(hashingCredentialValue "$CREDENTIAL_HASH_3_PARAM" "2abfcd4d-92a9-4b64-b32e-fa945325ada7" "4e0b8030-3feb-4dd4-b98c-6ce60654e9e4")
    echo "Hash for 3 param: $CRED_HASH"
    CRED_HASH=$(hashingCredentialValue "3_P" "2abfcd4d-92a9-4b64-b32e-fa945325ada7" "4e0b8030-3feb-4dd4-b98c-6ce60654e9e4")
    echo "Hash for unknown: $CRED_HASH"
}

testCryptingCredentialValue() {

    PUBLIC_KEY="-----BEGIN PUBLIC KEY-----\nMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAoAb87iHGF4kWDlrApt2V\ngJagpzheJrzk7Y64pD3xBvlO011TJgKJptWEzO6ejJLJK0F8G1bG23Q2yoPkX/j1\n58fSXnlz3o5Jj/mOl46X8rCcwAPYx3yZ3LLUbyKYLfyfBcStj4C/7U4Symb6fpgc\n1XxQ/shBRxq7XBUtQ//XGMlszUeiwTpQAh9dFaX0gKR0EDooRFD695HiRRrECcKx\nFdJ7WuUOCLcy9JBwss3lFK7H+Z+zS99RNvulhyTsJWo0ZRHfYm7K5itYq+Rn9skg\noGC2xc16QP9ZrONvTLW1HwmjOAba7Hv2bIU2iKI7aMHz6iWUD49aorhsJzcSrQtS\nubKe7nNuLDRlcbg2SWihuDhVGKJJpnufy23svUTRtbOEi5kSmE6/Oe8yeXkogFrM\nD2gfxX000s+0P/OsVDXoMF7j781fKzkkbR7X8AJG1/CJeN4dpqJKk/pvNYJmM+Iq\nCKSTrYUCrlyIhXJ8bAPpqMu7fF0aZkDtWun7wjMIDDHgaLT9eNPFlK2V6dBcgptQ\nqDN/0GaWBI/Aqoz67q/wTKHuqgh4pOMp5cK3J9z85sZtS53Q/y+5iGvgwsZOW5ox\n6EaV5hPPRZJgGA1cc+qWXHhN5Gbw011bSQZoq3g8Uw7TukoWiNbLhY9qNAlKlU/r\npiE9edQM7dgkjwgC/e9713kCAwEAAQ==\n-----END PUBLIC KEY-----"

    CRED_CRYPTED=$(cryptingCredentialValue "$PUBLIC_KEY" "VALUE_TO_ENCRYPT")
    echo "Crypted value: $CRED_CRYPTED"
}


testIsPlatformTeamExisting() {

    loginToPlatform
    TEAM_NAME="API Development"
    TEAM_GUID=$(isPlatformTeamExisting $PLATFORM_ORGID "$TEAM_NAME")
    echo "FoundTeamGuid:$TEAM_GUID"
    TEAM_NAME="API Development fake"
    TEAM_GUID=$(isPlatformTeamExisting $PLATFORM_ORGID "$TEAM_NAME")
    echo "FoundTeamGuid:$TEAM_GUID"
}

testSanitizingAppName() {
    V7_APP_NAME="Test with space"

    V7_APP_NAME_TMP=${V7_APP_NAME// /-}
    V7_APP_NAME_SANITIZED=${V7_APP_NAME_TMP//\//-}

    echo "Orginal:$V7_APP_NAME - Santitized:$V7_APP_NAME_SANITIZED"

}

testSanitizing() {
    INPUT="This is a long string with / in the middle"
    echo $(sanitizeName "$INPUT")
}


testPreprodEnv() {
    axway config set env preprod
    CENTRAL_URL="https://apicentral.qa.ampc.axwaytest.net"
    loginToPlatform
    CENTRAL_URL=$(getCentralURL)
    echo "Found Central url: $CENTRAL_URL"
    axway config set env prod
}

testJqAndCounter() {

    CREDENTIAL_LIST=$LOGS/app-735f5515-9c13-4c97-ab25-0651f5a8ffb6-apikeys.json
    CREDENTIAL_NUMBER=`jq length $CREDENTIAL_LIST`
    echo $CREDENTIAL_NUMBER

    if [[ $CREDENTIAL_NUMBER > 0 ]]
    then

        for (( i=0; i<$CREDENTIAL_NUMBER; i++ )) ; {
            # extract information
            CREDENTIAL_VALUE=$(cat $CREDENTIAL_LIST | jq -rc '.['$i']')
            echo "$i = $CREDENTIAL_VALUE"
        }
    fi
}

testJqEmpty() {
    
    echo "$PWD"
    V7_API_ID="48f13e00-a222-4f8e-ad1a-8e7d083ebe65" 
    #V7_API_ID="02822eb6-32c8-4fab-bfe0-571dbbf8aabe"
    ASSET_RESOURCE_CRD_ID=$(jq -rc '.[].metadata.references[] | select(.kind == "CredentialRequestDefinition").id' ../Logs/api-srv-control=$V7_API_ID-asset-resources.json)

    if [[ $ASSET_RESOURCE_CRD_ID == null ]]
    then
        echo "issue null"
    fi

    if [[ $ASSET_RESOURCE_CRD_ID == '' ]] 
    then 
        echo "issue empty"
    else
        if [[ $ASSET_RESOURCE_CRD_ID != null ]]
        then
            echo "OK:$ASSET_RESOURCE_CRD_ID"
            CREDENTIAL_REQUEST_DEFINITION_ID_FOUND=$ASSET_RESOURCE_CRD_ID
        else
            echo "issue2"
        fi
    fi
}

testEmptyFile() {
    FILE_NAME="$LOGS/credential-107f58a7-fb4b-4e4b-9f94-6cc1d643cb46-created.json"

    FILE_LENGTH=$(jq length $FILE_NAME)
    echo "FILE_LENGTH=$FILE_LENGTH-"
   	ATTEMPT_MAX=5
	SLEEP_TIME=1

	until [ $ATTEMPT_MAX -le 0 ]
	do
		echo "count: $ATTEMPT_MAX - sleep time = $SLEEP_TIME"

        echo "Reading DB..."

		# find the credential associated to the Marketplace credentials
		if [[ $FILE_LENGTH != '' && $FILE_LENGTH != 0 ]] 
		then
			# there is something in the file
			echo "We found something...."
			ATTEMPT_MAX=0
		else
			echo "Go to sleep..."
			# sleep a little to get some time 
			sleep $SLEEP_TIME
            # reduce the number of attempts
			((ATTEMPT_MAX=ATTEMPT_MAX-1))
			# increase the sleep time for next time
			((SLEEP_TIME=SLEEP_TIME+1))
		fi

	done
}

testStoppingLoop() {

    MAPPING_NUMBER=`jq length $LOGS/mapping-.json`
    FOUND=0
    COUNTER=0

    for (( i=0; i<$MAPPING_NUMBER; i++ )) ; {
        # extract information
        MAPPING_VALUE=$(cat $LOGS/mapping-.json | jq -rc '.['$i']')
        echo "$i = $MAPPING_VALUE"

        if [[ $i == 2 ]] then
            break
        fi
    }
 
}

testString () {

    CRD_NAME="dev-keycloak-lbean022-oauth-idp"

    if [[ $CRD_NAME == *$CREDENTIAL_DEFINTION_EXTERNAL_ID ]]
    then
        echo "$CRD_NAME end with $CREDENTIAL_DEFINTION_EXTERNAL_ID"
    else
        echo "test failed" 
    fi

    if [[ $CRD_NAME == $CREDENTIAL_DEFINTION_EXTERNAL_ID ]]
    then
        echo "test failed"
    else
        echo "$CRD_NAME Not equal $CREDENTIAL_DEFINTION_EXTERNAL_ID" 
    fi

    CRD_NAME="oauth-secret"
    if [[ $CRD_NAME == $CREDENTIAL_DEFINTION_OAUTH_PUBLIC_KEY || $CRD_NAME == $CREDENTIAL_DEFINTION_OAUTH_SECRET ]]
    then
        echo "$CRD_NAME = ($CREDENTIAL_DEFINTION_OAUTH_PUBLIC_KEY or $CREDENTIAL_DEFINTION_OAUTH_SECRET)"
    else
        echo "test failed"
    fi

    CRD_NAME="oauth-public-key"
    if [[ $CRD_NAME == $CREDENTIAL_DEFINTION_OAUTH_PUBLIC_KEY || $CRD_NAME == $CREDENTIAL_DEFINTION_OAUTH_SECRET ]]
    then
        echo "$CRD_NAME = ($CREDENTIAL_DEFINTION_OAUTH_PUBLIC_KEY or $CREDENTIAL_DEFINTION_OAUTH_SECRET)"
    else
        echo "test failed"
    fi
}


testAddingJson() {
    REQUIRED_FIELDS="$1"
    OUTPUT_FILE=$LOGS/tmp.json

    echo "Adding Required fields: $REQUIRED_FIELDS"

    FIELD_NUMBER=$(echo $REQUIRED_FIELDS | jq length)

    #echo "FIELD_NUMBER=$FIELD_NUMBER-"

    if [[ $FIELD_NUMBER != '' && $FIELD_NUMBER != 0 ]]
    then
        echo "{\"data\":{" > $OUTPUT_FILE
        for (( i=0; i<$FIELD_NUMBER; i++ )) ; {

            FIELD_NAME=$(echo $REQUIRED_FIELDS | jq -rc '.['$i']')

            if [[ $i == 0 ]]
            then
                echo "\"$FIELD_NAME\":\"dummy\"" >> $OUTPUT_FILE
            else
                echo ",\"$FIELD_NAME\":\"dummy\"" >> $OUTPUT_FILE
            fi
        }
        echo "}}" >> $OUTPUT_FILE

        # combine files
        jq --argjson data "$(jq '.data' $OUTPUT_FILE)" '.data = $data' ./mkt-application-appID-credential-credID.json > $LOGS/output.json

        cat $LOGS/output.json

        deleteFile "$OUTPUT_FILE"
        deleteFile $LOGS/output.json

    fi
}

testFindFieldValueFromCRD() {
    local FIELD_NAME="applicationType"
    local CRD_FILE="./crds-definition.json"
    local FIELD_VALUE="Dummy"

    FIELD_PATH=".[].spec.schema.properties.$FIELD_NAME"
    FIELD_DEFINITION=$(cat $CRD_FILE | jq -rc ''$FIELD_PATH'')

    FIELD_DEFAULT_VALUE=$(echo $FIELD_DEFINITION | jq -rc '.default')
    if [[ $FIELD_DEFAULT_VALUE != null ]]
    then
        FIELD_VALUE=$FIELD_DEFAULT_VALUE
    else
        echo "no default value, trying the enum..."
        # try the enum
        FIELD_ENUM=$(echo $FIELD_DEFINITION | jq -rc '.enum')

        if [[ $FIELD_ENUM != null ]]
        then
            # we take the 1st one
            FIELD_VALUE=$(echo $FIELD_DEFINITION | jq -rc '.enum[0]')
        fi
    fi

    echo "$FIELD_VALUE"

}

loginFromApi() {
    CLIENT_ID="sa-for-cli_a1d6e0a8-131f-4c1c-9d47-b4b357d00294"
    CLIENT_SECRET="f7b87aca-ab3e-4156-abc9-932a253e9519"  

    BASIC_AUTH=$(echo -ne "$CLIENT_ID:$CLIENT_SECRET" | base64 --wrap 0)
   
    curl -s --location "https://login.axway.com/auth/realms/Broker/protocol/openid-connect/token" --header 'Content-Type: application/x-www-form-urlencoded' --header 'Authorization: Basic '$BASIC_AUTH --data-urlencode 'grant_type=client_credentials' --data-urlencode 'scope=openid' --data-urlencode 'client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer'  > $LOGS/connect.json

#	PLATFORM_ORGID=$(axway auth list --json | jq -r '.[0] .org .id')
	PLATFORM_TOKEN=$(cat $LOGS/connect.json | jq -rc '.access_token ')
    echo "Token:$PLATFORM_TOKEN"
#	ORGANIZATION_REGION=$(axway auth list --json | jq -r '.[0] .org .region ')
#	USER_GUID=$(axway auth list --json | jq -r '.[0] .user .guid ')
	echo " and set CENTRAL_URL to " 
	CENTRAL_URL=$(getCentralURL)
	echo "$CENTRAL_URL"
	echo "OK we are good."

}

testMarketplaceRetrieval() {
    loginFromApi

    getMarketplaceProductIdFromProductName "Documentation product"
}

testAPIisRetired() {

# from LBEAN004
    API_INFO=$(getAPIM_API_Info "a6814243-cb9c-4e9b-936d-3042d3dad459")

    retired=$(echo $API_INFO | jq -rc '.retired')
    name=$(echo $API_INFO | jq -rc '.name')
    # not retired - false expected
    if [[ "$retired" == "false" ]] then
        echo "API ($name) not retired" >&2
    fi

    # retired - true expected
    API_INFO=$(getAPIM_API_Info "b3e1330a-56b1-4484-86fe-966c89b0c793")

    retired=$(echo $API_INFO | jq -rc '.retired')
    name=$(echo $API_INFO | jq -rc '.name')
    if [[ "$retired" == "true" ]] then
        echo "API ($name) is retired" >&2
    fi

}

testGetAPIM_API_Info()
{
    getAPIM_API_Info "a6814243-cb9c-4e9b-936d-3042d3dad459"
}

################# MAIN #################
#testHashingCredential
#testSanitizingAppName
#testIsPlatformTeamExisting
#testSanitizing
#testMergeMapping
#testPreprodEnv
#testJqAndCounter
#testJqEmpty
#testEmptyFile
#testStoppingLoop
#testString
#testAddingJson ""
#testAddingJson "[\"idpTokenURL\",\"second\"]"
#testFindFieldValueFromCRD
#testCryptingCredentialValue
#loginFromApi
#testMarketplaceRetrieval
#testGetAPIM_API_Info
testAPIisRetired