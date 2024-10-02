# some variables
CREDENTIAL_TYPE_APIKEY="APIKEY"
CREDENTIAL_TYPE_OAUTH="OAUTH"
CREDENTIAL_TYPE_EXTERNAL="EXTERNAL"
TBD_VALUE="TBD"
CREDENTIAL_DEFINTION_BASIC_AUTH="http-basic"
CREDENTIAL_DEFINTION_APIKEY="api-key"
CREDENTIAL_DEFINTION_OAUTH_SECRET="oauth-secret"
CREDENTIAL_DEFINTION_OAUTH_PUBLIC_KEY="oauth-public-key"
CREDENTIAL_DEFINTION_OAUTH_SECRET_2="oauth-client-id-secret"
CREDENTIAL_DEFINTION_OAUTH_PUBLIC_KEY_2="oauth-client-id-private-key"
CREDENTIAL_DEFINTION_EXTERNAL_ID="-oauth-idp"
CREDENTIAL_HASH_2_PARAM="2"
CREDENTIAL_HASH_3_PARAM="3"

# For debugging purpose
DEBUG=0

# For keeping files
KEEP_FILE=0

##########################################################
# Deleting file - check if the file should be kept or not
#
###########################################################
function deleteFile()
{
	if [[ $KEEP_FILE == 0 ]]
	then
		rm -rf $1
	fi
}

#########################
# Debug display
#
# $1: message
#########################
function logDebug()
{
	if [[ $DEBUG == 1 ]]
	then
		echo "DEBUG- $1" >&2
	fi
}

#########################################
# Error management after a command line 
# $1: error message
# $2: (optional) file name referene
# $3: TODO - error criticity
#########################################
function error_exit {
   if [ $? -ne 0 ]
   then
      echo "$1" >&2 
      if [ $2 ]
      then
         echo "See $2 file for errors" >&2 
      fi
	  error=1
      exit 1
   fi
}

######################################
# Error management after a curl POST #
# $1 = message to display            #
# $2 = file name                     #
######################################
function error_post {
	# search in input file if there are some errors
	if [ $2 ] # safe guard
	then
		errorFound=`cat $2 | jq -r '.errors'`
		if [[ $errorFound != null ]]
		then
			echo "$1. Please check file $2"
			error=1
			exit 1
		fi
	fi
}

############################
# Connectivity to Amplify
############################
function loginToPlatform {

	echo "Connecting to Amplify platform with Axway CLI"
	if [[ $CLIENT_ID == "" ]]
	then
		echo "No client id supplied => login via browser"
		axway auth login
	else
		echo "Service account supplied => login headless"
		axway auth login --client-id $CLIENT_ID --secret-file "$CLIENT_SECRET"
	fi

    error_exit "Problem with authentication to your account. Please, verify your credentials"

	# retrieve the organizationId of the connected user
	echo ""
	echo "Retrieving the organization ID / Token and Region..."
	PLATFORM_ORGID=$(axway auth list --json | jq -r '.[0] .org .id')
	PLATFORM_TOKEN=$(axway auth list --json | jq -r '.[0] .auth .tokens .access_token ')
	ORGANIZATION_REGION=$(axway auth list --json | jq -r '.[0] .org .region ')
	USER_GUID=$(axway auth list --json | jq -r '.[0] .user .guid ')
	echo " and set CENTRAL_URL to " 
	CENTRAL_URL=$(getCentralURL)
	echo "$CENTRAL_URL"
	echo "OK we are good."
}


#######################################
# Check the team existance in platform
#
# Input: 
# - ORG_ID
# - TEAM_NAME
#
# Output
# - TEAM_GUID with correct guid or "" if not existing.
#######################################
isPlatformTeamExisting() {

    ORG_ID=$1
    TEAM_NAME="$2"
    # for now we assume we did not find it.
    TEAM_GUID=""

    # read the team
    axway team view $ORG_ID "$TEAM_NAME" > "$LOGS_DIR/team.txt"
    TEAM_GUID_TMP=$(cat "$LOGS_DIR/team.txt" | grep "Team GUID")

    if [[ $TEAM_GUID_TMP != "" ]] 
    then
        #Output: Team GUID:    d9120f39-88d1-4977-bc56-5dd7d7335a18
        # return only GUID
        TEAM_GUID=${TEAM_GUID_TMP:14}
    fi

	rm -rf $LOGS_DIR/team.txt
    echo $TEAM_GUID
}

#############################################
# Get organization Name based on the ORG_ID
# 
# Input: ORG_ID
#############################################
getAPIM_OrganizationName()
{
    V7_ORGID=$1

    retVal=$(getFromApiManager "organizations/$V7_ORGID" "$LOGS_DIR/organization.json" ".name")
    
	rm -rf $LOGS_DIR/organization.json
    
    echo "$retVal"
}

#############################################
# Get API Name based on the API_ID
# 
# Input: API_ID
#############################################
getAPIM_APIName()
{
    V7_API_ID=$1

    retVal=$(getFromApiManager "proxies/$V7_API_ID" "$LOGS_DIR/api-$V7_API_ID.json" ".name")

	deleteFile $LOGS_DIR/api-"$V7_API_ID".json
    
    echo "$retVal"
}

#############################################
# Get retired information based on the API_ID
# 
# Input: API_ID
#############################################
getAPIM_APIRetired()
{
    V7_API_ID=$1

    retVal=$(getFromApiManager "proxies/$V7_API_ID" "$LOGS_DIR/api-$V7_API_ID.json" ".retired")

	rm -rf $LOGS_DIR/api-"$V7_API_ID".json
    
    echo "$retVal"
}

################################################
# Retrieve specific credential for a given APP 
# 
# Input:
# - $1: Application ID
# - $2: credentials type (APIKEY / OAUTH / EXTERNAL)
# - $3: output file
################################################
function getAPIM_Credentials() {
	local V7_APP_ID=$1
	local V7_CREDENTIAL_TYPE=$2
	local OUTPUT_FILE=$3
	local ENDPOINT=""

    case $V7_CREDENTIAL_TYPE in
        "$CREDENTIAL_TYPE_APIKEY")
            ENDPOINT="applications/$V7_APP_ID/apikeys"
            ;;
        "$CREDENTIAL_TYPE_OAUTH")
            ENDPOINT="applications/$V7_APP_ID/oauth"            
            ;;
        "$CREDENTIAL_TYPE_EXTERNAL")
            ENDPOINT="applications/$V7_APP_ID/extclients"
			;;
    esac

	getFromApiManager "$ENDPOINT" "$OUTPUT_FILE" ""
}

##########################################################
# Putting data to the AMPI Manager                       #
#                                                        #
# $1: url to call                                        #
# $2: payload                                            #
# $3: output file                                        #
##########################################################
function putToApiManager() {

    ENDPOINT=$1

    # encode user/password
    AUTH=$(echo -ne "$APIMANAGER_USER:$APIMANAGER_PASSWORD" | base64 --wrap 0)

	if [[ $3 == "" ]]
	then 
		# just in case...
		outputFile=postToApiManager.json
	else
		outputFile=$3
	fi

    curl -s -X PUT -k -H "Content-Type: application/json" -H "Authorization: Basic $AUTH" https://$APIMANAGER_HOST:$APIMANAGER_PORT/api/portal/$APIMANAGER_API_VERSION/$ENDPOINT -d "`cat $2`"> "$outputFile"

}


##########################################################
# Posting data to the AMPI Manager                       #
#                                                        #
# $1: url to call                                        #
# $2: payload                                            #
# $3: output file                                        #
##########################################################
function postToApiManagerUrlEncoded() {

	postToApiManagerWithHeader $1 $2 "application/x-www-form-urlencoded" $3
}

function postToApiManagerJson() {
	postToApiManagerWithHeader $1 $2 "application/json" $3
}

##########################################################
# Posting data to the AMPI Manager                       #
#                                                        #
# $1: url to call                                        #
# $2: payload                                            #
# $3: spectif Header content type                        #
# $4: output file                                        #
##########################################################
function postToApiManagerWithHeader() {

    ENDPOINT=$1

    # encode user/password
    AUTH=$(echo -ne "$APIMANAGER_USER:$APIMANAGER_PASSWORD" | base64 --wrap 0)

	if [[ $4 == "" ]]
	then 
		# just in case...
		outputFile=postToApiManager.json
	else
		outputFile=$4
	fi

    curl -s -k -H "Content-Type: $3" -H "Authorization: Basic $AUTH" https://$APIMANAGER_HOST:$APIMANAGER_PORT/api/portal/$APIMANAGER_API_VERSION/$ENDPOINT -d "`cat $2`"> "$outputFile"

}

##########################################################
# Getting data from the AMPI Manager                     #
# either return the entire object or the portion         #
# specified with $2 as a jq extract expression           #
#                                                        #
# $1 (mandatory): endpoint to call                       #
# $2 output file where to put result                     #
# $3 (optional) jq to extract value                      #
##########################################################
function getFromApiManager() {

    ENDPOINT=$1

    # encode user/password
    AUTH=$(echo -ne "$APIMANAGER_USER:$APIMANAGER_PASSWORD" | base64 --wrap 0)

	if [[ $2 == "" ]]
	then 
		# just in case...
		outputFile=getFromAPIMResult.json
	else
		outputFile=$2
	fi

    curl -s -k -H "Authorization: Basic $AUTH" https://$APIMANAGER_HOST:$APIMANAGER_PORT/api/portal/$APIMANAGER_API_VERSION/$ENDPOINT > "$outputFile"

	if [[ $3 != "" ]]
	then
        # apply the JQ pattern
		echo `cat $outputFile | jq -r "$3"`
	fi
}


#########################################################################
# Find the Marketplace productID having specific productName
# 
# $1: Product name
# ReturnValue: ProductId
#########################################################################
function getMarketplaceProductIdFromProductName {

	PRODUCT_NAME=$1

	NAME_WITHOUTSPACE=${PRODUCT_NAME// /-}
	TEMP_FILE_NAME="$LOGS_DIR/mkt-product-$NAME_WITHOUTSPACE-tmp.json"

    PRODUCT_NAME_FOR_QUERY=$(sanitizeNameForQuery "$PRODUCT_NAME")

	# call MP API
	getFromMarketplace "$MARKETPLACE_URL/api/v1/products?limit=10&offset=0&search=$PRODUCT_NAME_FOR_QUERY&sort=-lastVersion.metadata.createdAt%2C%2Bname" "" $TEMP_FILE_NAME
	# /!\ the above request can return multiple product as search use: *$NAME* => need to filter the content to get the real one

	# select appropriate product based on the real title
	cat $TEMP_FILE_NAME | jq -r '[ .items[] | select( .title=="'"$PRODUCT_NAME"'" ) ]' | jq -rc '.[] | {productId: .id, productLatestVersionId: .latestVersion.id}'

	# remove intermediate files
	deleteFile "$TEMP_FILE_NAME"

}

#########################################################################
# Find the Marketplace planID having specific productID and planName
# 
# $1: ProductID
# $2: Plan name
# ReturnValue: PlanId
#########################################################################
function getMarketplacePlanIdFromPlanName {

	PRODUCT_ID=$1
    PLAN_NAME=$2

	NAME_WITHOUTSPACE=${PRODUCT_NAME// /-}
	TEMP_FILE_NAME="$LOGS_DIR/mkt-product-$NAME_WITHOUTSPACE-plans-tmp.json"

    PRODUCT_NAME_FOR_QUERY=$(sanitizeNameForQuery "$PRODUCT_NAME")

	# call MP API
	getFromMarketplace "$MARKETPLACE_URL/api/v1/products/$PRODUCT_ID/plans?limit=10&offset=0&plan.state=active" "" $TEMP_FILE_NAME

	# select appropriate product based on the real title
	cat $TEMP_FILE_NAME | jq -r '[ .items[] | select( .title=="'"$PLAN_NAME"'" ) ]' | jq -rc '.[].id'

	# remove intermediate files
	deleteFile "$TEMP_FILE_NAME"
}



##########################################################
# Getting data from the marketplace                      #
# either return the entire object or the portion         #
# specified with $2 as a jq extract expression           #
#                                                        #
# $1 (mandatory): url to call                            #
# $2 (optional): jq expression to extract information    #
# $3 output file where to put result                     #
##########################################################
function getFromMarketplace() {

	outputFile="$3"

	curl -s -k -L $1 -H "Content-Type: application/json" -H "X-Axway-Tenant-Id: $PLATFORM_ORGID" --header 'Authorization: Bearer '$PLATFORM_TOKEN > "$outputFile"

	if [[ $2 != "" ]]
	then
		echo `cat $outputFile | jq -r "$2"`
	fi
}

###################################
# Posting data to the marketplace #
# and get the data into a file    #
#                                 #
# $1: url to call                 #
# $2: payload                     #
# $3: output file                 #
###################################
function postToMarketplace() {

	if [[ $3 == "" ]]
	then 
		# just in case...
		outputFile="$LOGS_DIR/postToMarketplaceResult.json"
	else
		outputFile=$3
	fi

	#echo "url for MP = "$1
	curl -s -k -L $1 -H "Content-Type: application/json" -H "X-Axway-Tenant-Id: $PLATFORM_ORGID" --header 'Authorization: Bearer '$PLATFORM_TOKEN -d "`cat $2`" > $outputFile
}



########################################
# Build CentralURl based on the region #
#                                      #
# Input: region                        #
# Output: CENTRAL_URL is set           #
########################################
function getCentralURL {

	if [[ $CENTRAL_URL == '' ]]
	then
		if [[ $ORGANIZATION_REGION == 'EU' ]]
		then
			# we are in France
			CENTRAL_URL="https://central.eu-fr.axway.com"
		else 
			if [[ $ORGANIZATION_REGION == 'AP' ]]
			then
				# we are in APAC
				CENTRAL_URL="https://central.ap-sg.axway.com"
			else
				# Default US region
				CENTRAL_URL="https://apicentral.axway.com"
			fi
		fi
	fi 

	echo $CENTRAL_URL
}

##########################################################
# Getting data from the Central                          #
# either return the entire object or the portion         #
# specified with $2 as a jq extract expression           #
#                                                        #
# with a retry mechanism                                 #
#                                                        #
# $1 (mandatory): url to call                            #
# $2 (optional): jq expression to extract information    #
# $3 output file where to put result                     #
##########################################################
getFromCentralWithRetry() {
	local URL=$1
	local JQ_EXPRESSION=$2
	local OUTPUT_FILE=$3
	local ATTEMPT_MAX=5
	local SLEEP_TIME=1

	until [ $ATTEMPT_MAX -le 0 ]
	do
		logDebug "count: $ATTEMPT_MAX - sleep time = $SLEEP_TIME"

		# find the credential associated to the Marketplace credentials
		getFromCentral "$URL" "$JQ_EXPRESSION" "$OUTPUT_FILE"
		FILE_LENGTH=$(jq length $OUTPUT_FILE)

		if [[ $FILE_LENGTH != '' && $FILE_LENGTH != 0 ]] 
		then
			# there is something in the file
			logDebug "We found something...."
			ATTEMPT_MAX=0
		else
			logDebug "Go to sleep..."
			# sleep a little to get some time for events to be processed
			sleep $SLEEP_TIME
            # reduce the number of attempts
			((ATTEMPT_MAX=ATTEMPT_MAX-1))
			# increase the sleep time for next time
			((SLEEP_TIME=SLEEP_TIME*2))
		fi

	done

	logDebug "Ending the search"
}

##########################################################
# Getting data from the Central                          #
# either return the entire object or the portion         #
# specified with $2 as a jq extract expression           #
#                                                        #
# $1 (mandatory): url to call                            #
# $2 (optional): jq expression to extract information    #
# $3 output file where to put result                     #
##########################################################
function getFromCentral() {

	outputFile="$3"

	curl -s -k -L "$1" -H "Content-Type: application/json" -H "X-Axway-Tenant-Id: $PLATFORM_ORGID" --header 'Authorization: Bearer '$PLATFORM_TOKEN > "$outputFile"

	if [[ $2 != "" ]]
	then
		echo `cat "$outputFile" | jq -r "$2"`
	fi
}

###################################
# Posting data to the Central     #
# and get the data into a file    #
#                                 #
# $1: url to call                 #
# $2: payload                     #
# $3: output file                 #
###################################
function putToCentral() {

	if [[ $3 == "" ]]
	then 
		# just in case...
		outputFile=putToCentralResult.json
	else
		outputFile=$3
	fi

	#echo "url for MP = "$1
	curl -s -X PUT $1 -H "Content-Type: application/json" -H "X-Axway-Tenant-Id: $PLATFORM_ORGID" --header 'Authorization: Bearer '$PLATFORM_TOKEN -d "`cat $2`" > $outputFile
}

#############################
# hashing the credentials so that agent can recognize them
# 2_PARAM - #APiKey and Internal Oauth - ID Secret (ex. ./hasher 2abfcd4d-92a9-4b64-b32e-fa945325ada7 4e0b8030-3feb-4dd4-b98c-6ce60654e9e4) 
# 3_PARAM - #External Oauth - ID --- ClientID (ex. ./hasher  2abfcd4d-92a9-4b64-b32e-fa945325ada7 - 4e0b8030-3feb-4dd4-b98c-6ce60654e9e4)
# Input parameters
# - type of Credential - 3_PARAM or 2_PARAM
# - CREDENTIAL_ID
# - CREDENTIAL_ID_SECRET
# Output - the corresponding hash
#############################
hashingCredentialValue() {

    CREDENTIAL_TYPE=$1
    CREDENTIAL_ID=$2
    CREDENTIAL_ID_SECRET=$3
	RETURN_VAL=""
    
    case $CREDENTIAL_TYPE in
        $CREDENTIAL_HASH_2_PARAM)
            RETURN_VAL=$($TOOL_DIR/hasher-windows-amd64 $CREDENTIAL_ID $CREDENTIAL_ID_SECRET)
            ;;
        $CREDENTIAL_HASH_3_PARAM)
            RETURN_VAL=$($TOOL_DIR/hasher-windows-amd64 $CREDENTIAL_ID "-" $CREDENTIAL_ID_SECRET)
            ;;
    esac

    echo "$RETURN_VAL"
}

#############################
# crypting the credentials so that Marketplace can recognize them
# run the tool ./keytool --public_key ./public_key.pem --data_file ./value.txt
#
# Input parameters
# - $1: file containing the public key
# - $2: value to encypt
# Output - the corresponding crypted value
#############################
cryptingCredentialValue() {
	echo "$2" > "$LOGS_DIR/value.txt"

	# tools output = fileName.encrypted
	$TOOL_DIR/keytool-windows-amd64 --public_key "$1" --data_file "$LOGS_DIR/value.txt"
	RETURN_VAL=$(cat "$LOGS_DIR/value.txt.encrypted")

	rm -rf $LOGS_DIR/value.txt.encrypted
	echo "$RETURN_VAL"
}

#############################################
# Sanitize name and remove space, backslash
# Input: String
# Output: Sanitized String
#############################################
sanitizeName() {

    INPUT="$1"
    # replace ' ' with '-'
    INPUT_TMP=${INPUT// /-}
    # replace '/' with '-'
    SANITIZED_NAME=${INPUT_TMP//\//-}

    echo "$SANITIZED_NAME"
}

######################################################
# Sanitize name by replacing space with HTML Code %20
# Input: String
# Output: Sanitized String
######################################################
sanitizeNameForQuery() {

    INPUT="$1"
    # replace ' ' with '%20'
    SANITIZED_NAME=${INPUT// /%20}

    echo "$SANITIZED_NAME"
}
