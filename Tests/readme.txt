products credential from MKT:
{"title":"Cybo","credentialRequestDefinition":{"id":"8a2e892f81ac3f620181b1911a5204e7"},"data":{"grantType":"client_credentials","idpTokenURL":"https://lbean022.lab.phx.axway.int:9043/auth/realms/Beano/protocol/openid-connect/token","tokenAuthMethod":"client_secret_basic","certificateMetadata":"tls_client_auth_subject_dn"}}

axway central get credentialrequestdefinitions -q metadata.id==8a2e892f81ac3f620181b1911a5204e7 -s emotional-salesman -o yaml

CRD from asset resources:																	Corresponding CRD on provider
emotional-salesman/dev-keycloak-lbean022-oauth-idp	- 8a2e892f81ac3f620181b1911a5204e7		dev-keycloak-lbean022-oauth-idp - 8a2e834a81ac407b0181b1911980038e			
emotional-salesman/api-key							- 8a2e8fa4801f983b0180202bc467048d		api-key 						- 8a2e8036801f98600180202bc2510487
emotional-salesman/oauth-secret						- 8a2e8fa4801f983b0180202bca120494		oauth-secret 					- 8a2e81f0801f99650180202bc579057f
emotional-salesman/oauth-public-key					- 8a2e8fa4801f983b0180202bcc760497		oauth-public-key 				- 8a2e8fa4801f983b0180202bcc760497 		

  
axway central get credentials -s apigtw-v77 -q metadata.references.name==banking* -o yaml > cred.yaml
axway central get accessrequest -s apigtw-v77 -q metadata.references.name==banking* -o yaml > accReq.yaml
axway central get managedapplications -s apigtw-v77 -q metadata.references.name==banking* -o yaml > managedApp.yaml

axway central apply -f accReq.yaml
axway central apply -f cred.yaml
axway central apply -f managedApp.yaml


CLI login -> browser:
 https://login.axway.com/auth/realms/Broker/protocol/openid-connect/auth?access_type=offline&client_id=amplify-cli&code_challenge=1I8uI5Dkhlon-qF3QUrvbEZ31SkXTCdDlSwpUp6L7Gg&code_challenge_method=S256&grant_type=authorization_code&redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Fcallback%2F22E5CDEA&response_type=code&scope=openid

API login:
echo -n "clientID:secret" | base64

curl --location --request POST 'https://login.axway.com/auth/realms/Broker/protocol/openid-connect/token' \
--header 'Content-Type: application/x-www-form-urlencoded' \
--header 'Authorization: Basic c2EtdGVzdF84Y2RlMWExOC0yYWViLTRiY2QtODVkNS1jZmI1M2VjOWVmYjQ6ZjU0MDlmYjMtYjNhZC00MjU3LWE4NjgtZTNmMzY4NGYxMmY1' \
--data-urlencode 'grant_type=client_credentials'


Before
APIKEY_1 addd077c-8ee4-4423-b27e-d43231e25588
After rotate
APIKEY_1 a889514d-8c4b-44b1-a3fe-e04debf4a5a3
