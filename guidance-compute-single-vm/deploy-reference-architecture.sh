#!/bin/bash

RESOURCE_GROUP_NAME="ra-single-vm-rg"
LOCATION="centralus"
ADMIN_PASSWORD=""
SSH_PUBLIC_KEY=""
KEYVAULT_NAME=""
KEYVAULT_SECRET_NAME=""
AUTHENTICATION_TYPE="adminPassword"

TEMPLATE_ROOT_URI=${TEMPLATE_ROOT_URI:="https://raw.githubusercontent.com/mspnp/template-building-blocks/roshar/securekeys/"}
# Make sure we have a trailing slash
[[ "${TEMPLATE_ROOT_URI}" != */ ]] && TEMPLATE_ROOT_URI="${TEMPLATE_ROOT_URI}/"

# For validating HTTP URIs only
URI_REGEX="^((?:https?://(?:(?:[a-zA-Z0-9$.+!*(),;?&=_-]|(?:%[a-fA-F0-9]{2})){1,64}(?::(?:[a-zA-Z0-9$.+!*(),;?&=_-]|(?:%[a-fA-F0-9]{2})){1,25})?@)?)?(?:(([a-zA-Z0-9\x00A0-\xD7FF\xF900-\xFDCF\xFDF0-\xFFEF]([a-zA-Z0-9\x00A0-\xD7FF\xF900-\xFDCF\xFDF0-\xFFEF-]{0,61}[a-zA-Z0-9\x00A0-\xD7FF\xF900-\xFDCF\xFDF0-\xFFEF]){0,1}\.)+[a-zA-Z\x00A0-\xD7FF\xF900-\xFDCF\xFDF0-\xFFEF]{2,63}|((25[0-5]|2[0-4][0-9]|[0-1][0-9]{2}|[1-9][0-9]|[1-9])\.(25[0-5]|2[0-4][0-9]|[0-1][0-9]{2}|[1-9][0-9]|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1][0-9]{2}|[1-9][0-9]|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1][0-9]{2}|[1-9][0-9]|[0-9]))))(?::\d{1,5})?)(/(?:(?:[a-zA-Z0-9\x00A0-\xD7FF\xF900-\xFDCF\xFDF0-\xFFEF;/?:@&=#~.+!*(),_-])|(?:%[a-fA-F0-9]{2}))*)?(?:\b|$)$"

validate() {
    for i in "${@:2}"; do
      if [[ "$1" == "$i" ]]
      then
        return 1 
      fi
    done
    
    return 0 
}

validateNotEmpty() {
    if [[ "$1" != "" ]]
    then
      return 1
    else
      return 0
    fi
}

showErrorAndUsage() {
  echo
  if [[ "$1" != "" ]]
  then
    echo "  error:  $1"
    echo
  fi
  echo "  usage:  $(basename ${0}) [options]"
  echo "  options:"
  echo "    -l, --location <location>"
  echo "    -o, --os-type <windows | linux>"
  echo "    -s, --subscription <subscription-id>"
  echo "    -p, --password <admin-password>"
  echo "    -k, --ssh-public-key <ssh-public-key>"
  echo "    -v, --keyvault <keyvault-name>"
  echo "    -n, --secret-name <keyvault-secret-name>"
  echo "    -t, --auth-type <adminPassword | sshPublicKey>"
  echo
  exit 1
}

if [[ $# < 1 ]]
then
  showErrorAndUsage
fi

while [[ $# > 0 ]]
do
  key="$1"
  case $key in
    -o|--os-type)
      OS_TYPE="$2"
      shift
      ;;
    -s|--subscription)
      # Explicitly set the subscription to avoid confusion as to which subscription
      # is active/default
      SUBSCRIPTION_ID="$2"
      shift
      ;;
    -l|--location)
      LOCATION="$2"
      shift
      ;;
	-p|--password)
      ADMIN_PASSWORD="$2"
      shift
      ;;
	-k|--ssh-public-key)
      SSH_PUBLIC_KEY="$2"
      shift
      ;;
	-v|--keyvault)
      KEYVAULT_NAME="$2"
      shift
      ;;
	-n|--secret-name)
      KEYVAULT_SECRET_NAME="$2"
      shift
      ;;
	-t|--auth-type)
      AUTHENTICATION_TYPE="$2"
      shift
      ;;
    *)
      showErrorAndUsage "Unknown option: $1"
    ;;
  esac
  shift
done

if validate $AUTHENTICATION_TYPE "adminPassword" "sshPublicKey";
then
  showErrorAndUsage "Invalid Auth Type : '${AUTHENTICATION_TYPE}'  Valid values are 'adminPassword' or 'sshPublicKey'"
fi

declare -A parameters=( ["-sshPublicKey"]="" ["-adminPassword"]="")

if [[ "$SSH_PUBLIC_KEY" != "" ]]; then
  parameters["-sshPublicKey"]=$SSH_PUBLIC_KEY
elif [[ "$ADMIN_PASSWORD" != "" ]]; then
  parameters["-adminPassword"]=$ADMIN_PASSWORD
elif [[ "$KEYVAULT_NAME" != "" ]] && [[ "$KEYVAULT_SECRET_NAME" != "" ]] && [[ "$AUTHENTICATION_TYPE" != "" ]]; then 
  secretJson=$(echo $(azure keyvault secret show -u "$KEYVAULT_NAME" -s "$KEYVAULT_SECRET_NAME" --json))
  secret=$(node ./parameters.js -v "$secretJson")
  parameters["-$AUTHENTICATION_TYPE"]=$secret
else
  showErrorAndUsage "<admin-password> OR <ssh-public-key> OR (<keyvault-name>, <keyvault-secret-name>, <auth-type>) must be provided"
fi

if ! [[ $SUBSCRIPTION_ID =~ ^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$  ]];
then
  showErrorAndUsage "Invalid Subscription ID"
fi

if validate $OS_TYPE "windows" "linux";
then
  showErrorAndUsage "Invalid OS Type: '${OS_TYPE}'  Valid values are 'windows' or 'linux'"
fi

if validateNotEmpty $LOCATION;
then
  showErrorAndUsage "Location must be provided"
fi

if grep -P -v $URI_REGEX <<< $TEMPLATE_ROOT_URI > /dev/null
then
  showErrorAndUsage "Invalid value for TEMPLATE_ROOT_URI: ${TEMPLATE_ROOT_URI}"
fi

echo
echo "Using ${TEMPLATE_ROOT_URI} to locate templates"
echo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VIRTUAL_NETWORK_TEMPLATE_URI="${TEMPLATE_ROOT_URI}templates/buildingBlocks/vnet-n-subnet/azuredeploy.json"
VIRTUAL_NETWORK_PARAMETERS_PATH="${SCRIPT_DIR}/parameters/${OS_TYPE}/virtualNetwork.parameters.json"
VIRTUAL_NETWORK_DEPLOYMENT_NAME="ra-single-vm-vnet-deployment"

VIRTUAL_MACHINE_TEMPLATE_URI="${TEMPLATE_ROOT_URI}templates/buildingBlocks/multi-vm-n-nic-m-storage/azuredeploy.json"
VIRTUAL_MACHINE_PARAMETERS_PATH="${SCRIPT_DIR}/parameters/${OS_TYPE}/virtualMachine.parameters.json"
VIRTUAL_MACHINE_DEPLOYMENT_NAME="ra-single-vm-deployment"

NETWORK_SECURITY_GROUP_TEMPLATE_URI="${TEMPLATE_ROOT_URI}templates/buildingBlocks/networkSecurityGroups/azuredeploy.json"
NETWORK_SECURITY_GROUP_PARAMETERS_PATH="${SCRIPT_DIR}/parameters/${OS_TYPE}/networkSecurityGroups.parameters.json"
NETWORK_SECURITY_GROUP_DEPLOYMENT_NAME="ra-single-vm-nsg-deployment"

# Get parameters from the parameter file and append 'protectedSettings' to it.
# Return JSON-formatted string containing all parameters.
# Example-
# {"protectedSettings":{"value":{"sshPublicKey":"","adminPassword":"<Your Password>"}},"virtualNetworkSettings":{"value":{"name":"ra-
# single-vm-vnet","addressPrefixes":["10.0.0.0/16"],"subnets":[{"name":"web","addressPrefix":"10.0.1.0/24"}],"dnsServers":
# []}}}
CMD="node ./parameters.js"
for key in "${!parameters[@]}"; do 
  CMD+=" $key ${parameters[$key]}";
done
CMD+=" -f "

VIRTUAL_MACHINE_PARAMETERS=$($CMD$VIRTUAL_MACHINE_PARAMETERS_PATH)

azure config mode arm

# Create the resource group, saving the output for later.
RESOURCE_GROUP_OUTPUT=$(azure group create --name $RESOURCE_GROUP_NAME --location $LOCATION --subscription $SUBSCRIPTION_ID --json) || exit 1

# Create the virtual network
echo "Deploying virtual network..."
azure group deployment create --resource-group $RESOURCE_GROUP_NAME --name $VIRTUAL_NETWORK_DEPLOYMENT_NAME \
--template-uri $VIRTUAL_NETWORK_TEMPLATE_URI --parameters-file $VIRTUAL_NETWORK_PARAMETERS_PATH \
--subscription $SUBSCRIPTION_ID || exit 1

echo "Deploying virtual machine..."
azure group deployment create --resource-group $RESOURCE_GROUP_NAME --name $VIRTUAL_MACHINE_DEPLOYMENT_NAME \
--template-uri $VIRTUAL_MACHINE_TEMPLATE_URI --parameters $VIRTUAL_MACHINE_PARAMETERS \
--subscription $SUBSCRIPTION_ID || exit 1

echo "Deploying network security group..."
azure group deployment create --resource-group $RESOURCE_GROUP_NAME --name $NETWORK_SECURITY_GROUP_DEPLOYMENT_NAME \
--template-uri $NETWORK_SECURITY_GROUP_TEMPLATE_URI --parameters-file $NETWORK_SECURITY_GROUP_PARAMETERS_PATH \
--subscription $SUBSCRIPTION_ID || exit 1

# Display json output
echo "==================================="

echo $RESOURCE_GROUP_OUTPUT

azure group deployment show --resource-group $RESOURCE_GROUP_NAME --name $VIRTUAL_NETWORK_DEPLOYMENT_NAME \
--subscription $SUBSCRIPTION_ID --json || exit 1

azure group deployment show --resource-group $RESOURCE_GROUP_NAME --name $VIRTUAL_MACHINE_DEPLOYMENT_NAME \
--subscription $SUBSCRIPTION_ID --json || exit 1

azure group deployment show --resource-group $RESOURCE_GROUP_NAME --name $NETWORK_SECURITY_GROUP_DEPLOYMENT_NAME \
--subscription $SUBSCRIPTION_ID --json || exit 1

echo "==================================="
