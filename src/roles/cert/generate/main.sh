#!/usr/bin/env bash
## INIT START ##
if [[ $DEBUG == "0" ]]
then 
  set -x 
fi  
# Get the directory where this script is located
current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Traverse up the directory tree to find the .github folder
github_dir="$current_dir"
while [ ! -d "$github_dir/.git" ] && [ "$github_dir" != "/" ]; do
  github_dir="$(dirname "$github_dir")"
done
# If the .github folder is found, set root_directory
if [ -d "$github_dir/.git" ]; then
  root_directory="$github_dir"
  if [[ $DEBUG == "0" ]]; then echo "The root directory is: $root_directory"; fi
else
  echo "Error: Unable to find .github folder."
fi
## INIT END ##

#################################################################
source $root_directory/commons/scripts/utils.sh
index_role_name=$(basename $ROLE_DIR)
role_name=$(yq e '.role.name' ${current_dir}/config.yaml)
openssl_san_file=$(yq e '.role.files.openssl-san' $current_dir/config.yaml)
openssl_san_file_path=$current_dir/$openssl_san_file

cp $openssl_san_file_path  ${ROLE_DIR}/$(basename $openssl_san_file_path)

errorHappened=1 # 0 is true, 1 is false

IFS=',' read -ra new_dns_entries <<< "${SAN_DNS_LIST}"

index=${#new_dns_entries[@]}
for dns_entry in "${new_dns_entries[@]}"; do
    sed -i "/^\[alt_names\]/a DNS.$index = $dns_entry" ${ROLE_DIR}/$(basename $openssl_san_file_path)
    ((index--))
done

IFS=',' read -ra new_ip_entries <<< "${SAN_IP_LIST}"

index=${#new_ip_entries[@]}
for ip_entry in "${new_ip_entries[@]}"; do
    sed -i "/^\[alt_names\]/a IP.$index = $ip_entry" ${ROLE_DIR}/$(basename $openssl_san_file_path)
    ((index--))
done

if [[ ${ROOT_CA_CERT} == "" ]]
then  
  openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:4096  -subj "/O=Loopy Example Inc./CN=root"  -keyout ${ROLE_DIR}/${ROOT_CA_KEY_NAME}  -out ${ROLE_DIR}/${ROOT_CA_CERT_NAME}
else
  if [[ ${ROOT_CA_KEY} == "" ]]
  then
    error "ROOT_CA_CERT is set but ROOT_CA_KEY is NOT set."
    exit 1
  fi
  if [[ ! -f ${ROOT_CA_CERT} ]] || [[ ! -f ${ROOT_CA_KEY} ]]
  then
    error "ROOT_CA_CERT or ROOT_CA_KEY file does not exist"
    error "ROOT_CA_CERT: ${ROOT_CA_CERT}, ROOT_CA_KEY: ${ROOT_CA_KEY}"
    exit 1
  fi
  cp ${ROOT_CA_CERT} ${ROLE_DIR}/${ROOT_CA_CERT_NAME}
  cp ${ROOT_CA_KEY} ${ROLE_DIR}/${ROOT_CA_KEY_NAME}  
fi

openssl req -nodes --newkey rsa:4096 -subj "/CN=${CN}/O=Loopy Example Inc."  --keyout ${ROLE_DIR}/${KEY_NAME} -out ${ROLE_DIR}/${CSR_NAME} -config ${ROLE_DIR}/$(basename $openssl_san_file_path)

openssl x509 -req -in ${ROLE_DIR}/${CSR_NAME} -CA ${ROLE_DIR}/${ROOT_CA_CERT_NAME} -CAkey ${ROLE_DIR}/${ROOT_CA_KEY_NAME} -CAcreateserial -out ${ROLE_DIR}/${CERT_NAME} -days 365 -sha256 -extfile ${ROLE_DIR}/$(basename $openssl_san_file_path) -extensions v3_req

############# VERIFY #############
result=1
echo "Verify certicate"
openssl x509 -in ${ROLE_DIR}/${CERT_NAME} -text
openssl verify -CAfile ${ROLE_DIR}/${ROOT_CA_CERT_NAME} ${ROLE_DIR}/${CERT_NAME}
if [[ $? == "0" ]]
then
  result=0
else 
  error "openssl verify failed"
  errorHappened=0
fi

if [[ $errorHappened == "0" ]]
then
  info "There are some errors in the role"
  stop_when_failed=$(is_positive ${STOP_WHEN_FAILED})
  if [[ ${stop_when_failed} == "0" ]]
  then
    die "STOP_WHEN_FAILED(${STOP_WHEN_FAILED}) is set and there are some errors detected so stop all process"
  else
    info "STOP_WHEN_FAILED(${STOP_WHEN_FAILED}) is NOT set so skip this error."
  fi
fi  

############# OUTPUT #############
echo "ROOT_CA_CERT_FILE_PATH=${ROLE_DIR}/${ROOT_CA_CERT_NAME}" >> ${OUTPUT_ENV_FILE}
echo "ROOT_CA_KEY_FILE_PATH=${ROLE_DIR}/${ROOT_CA_KEY_NAME}" >> ${OUTPUT_ENV_FILE}
echo "CERT_FILE_PATH=${ROLE_DIR}/${CERT_NAME}" >> ${OUTPUT_ENV_FILE}
echo "KEY_FILE_PATH=${ROLE_DIR}/${KEY_NAME}" >> ${OUTPUT_ENV_FILE}

############# REPORT #############
echo "${index_role_name}::$?" >> ${REPORT_FILE}
