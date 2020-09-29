#!/bin/bash

# Install bosh in Azure
export SUBSCRIPTION_ID=957e8e87-4448-46ba-bc0f-5406c18fcc5a
export APPLICATION_ID=2419eb4d-9a22-48bd-bef8-8e8192e099fd
export TENANT_ID=17f8330f-a4d6-4ef9-b661-8b2aefc4e1ca
export LOCATION="West Europe"
export RES_GROUP="bosh-res-group"
export VNET="bosh-net"
export STORAGE="boshstorechudinov"
export IP="bosh-public-ip"

az account set --subscription $SUBSCRIPTION_ID

# Create a new secret for Azure service principal
export SERVICE_PRINCIPAL_SECRET=$(az ad app credential reset --id  $APPLICATION_ID --append --query "password" --out tsv)

az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Compute

az group create --name $RES_GROUP --location "$LOCATION"

az network vnet create --name $VNET --address-prefixes 10.0.0.0/8 --resource-group $RES_GROUP --location "$LOCATION" --dns-server 8.8.8.8
az network vnet subnet create --name bosh --address-prefix 10.0.0.0/24 --vnet-name $VNET --resource-group $RES_GROUP

az network nsg create --resource-group $RES_GROUP --location "$LOCATION" --name nsg-bosh
az network nsg create --resource-group $RES_GROUP --location "$LOCATION" --name nsg-cf

az network nsg rule create --resource-group $RES_GROUP --nsg-name nsg-bosh --access Allow --protocol Tcp --direction Inbound --priority 200 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'ssh' --destination-port-range 22
az network nsg rule create --resource-group $RES_GROUP --nsg-name nsg-bosh --access Allow --protocol Tcp --direction Inbound --priority 201 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'bosh-agent' --destination-port-range 6868
az network nsg rule create --resource-group $RES_GROUP --nsg-name nsg-bosh --access Allow --protocol Tcp --direction Inbound --priority 202 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'bosh-director' --destination-port-range 25555
az network nsg rule create --resource-group $RES_GROUP --nsg-name nsg-bosh --access Allow --protocol '*' --direction Inbound --priority 203 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'dns' --destination-port-range 53

az network nsg rule create --resource-group $RES_GROUP --nsg-name nsg-cf --access Allow --protocol Tcp --direction Inbound --priority 201 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'cf-https' --destination-port-range 443
az network nsg rule create --resource-group $RES_GROUP --nsg-name nsg-cf --access Allow --protocol Tcp --direction Inbound --priority 202 --source-address-prefix Internet --source-port-range '*' --destination-address-prefix '*' --name 'cf-log' --destination-port-range 4443

az network public-ip create --name $IP --allocation-method Static --resource-group $RES_GROUP --location "$LOCATION" --sku Basic 

az storage account create --name $STORAGE --resource-group $RES_GROUP --location "$LOCATION"
export STORAGE_KEY=$(az storage account keys list --account-name $STORAGE --resource-group $RES_GROUP --query [0].value -o tsv)

az storage container create --name bosh --account-name $STORAGE --account-key $STORAGE_KEY
az storage container create --name stemcell --account-name $STORAGE --account-key $STORAGE_KEY --public-access blob
az storage container list --account-name $STORAGE --account-key $STORAGE_KEY

az storage table create --name stemcells --account-name $STORAGE --account-key $STORAGE_KEY
az storage table list --account-name $STORAGE --account-key $STORAGE_KEY

cd ..

mkdir bosh-1 && cd bosh-1
git clone https://github.com/cloudfoundry/bosh-deployment

bosh create-env bosh-deployment/bosh.yml \
    --state=state.json \
    --vars-store=creds.yml \
    -o bosh-deployment/azure/cpi.yml \
    -v director_name=bosh-1 \
    -v internal_cidr=10.0.0.0/24 \
    -v internal_gw=10.0.0.1 \
    -v internal_ip=10.0.0.6 \
    -v vnet_name=$VNET \
    -v subnet_name=bosh \
    -v subscription_id=$SUBSCRIPTION_ID \
    -v tenant_id=$TENANT_ID \
    -v client_id=$APPLICATION_ID \
    -v client_secret=$SERVICE_PRINCIPAL_SECRET \ 
    -v resource_group_name=$RES_GROUP \
    -v storage_account_name=$STORAGE \
    -v default_security_group=nsg-bosh \
