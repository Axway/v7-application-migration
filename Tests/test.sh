#!/bin/bash

# Guillaume repo = https://git-ext.ecd.axway.com/cso-reusable/api-management/amplify-components/-/tree/main/marketplace/migration/engie/app-migration-tool-v2?ref_type=heads

# Sourcing user-provided env properties
source ../config/envCB.properties

# add all utility functions
source ../utils.sh

# Global variables
LOGS=./logs
TOOL_DIR=../Tools
CONFIG_DIR=../config

testMergeMapping() {

    jq --slurpfile file2 ./File2.json '(.Mapping += $file2)' ./File1.json > ./generated_file-tmp.json
    jq --slurpfile file2 ./File2.json '(.Mapping += $file2)' ./generated_file-tmp.json > ./$LOGS/generated_file.json
    rm ./generated_file-tmp.json
}

testHashingCredential() {
    CRED_HASH=$(hashingCredentialValue "2_PARAM" "2abfcd4d-92a9-4b64-b32e-fa945325ada7" "4e0b8030-3feb-4dd4-b98c-6ce60654e9e4")
    echo "Hash for : $CRED_HASH"
    CRED_HASH=$(hashingCredentialValue "3_PARAM" "2abfcd4d-92a9-4b64-b32e-fa945325ada7" "4e0b8030-3feb-4dd4-b98c-6ce60654e9e4")
    echo "Hash for : $CRED_HASH"
    CRED_HASH=$(hashingCredentialValue "3_P" "2abfcd4d-92a9-4b64-b32e-fa945325ada7" "4e0b8030-3feb-4dd4-b98c-6ce60654e9e4")
    echo "Hash for : $CRED_HASH"
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

################# MAIN #################
#testHashingCredential
#testSanitizingAppName
#testIsPlatformTeamExisting
testSanitizing
testMergeMapping