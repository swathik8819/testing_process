#!/bin/bash

##Arguments Usage
#Git_Repo=$4
#Git_Token=$5
#Event_Publisher=$6
#webhookURL=$7

touch ./deleted_files.lst
touch ./changed_files.lst

detect_changes () {
    if [ "0000000000000000000000000000000000000000" = "$1" ]; then
            git diff-tree --diff-filter=d --no-commit-id --name-only -r $2 > ./changed_files.lst &&
            git diff-tree --diff-filter=D --no-commit-id --name-only -r $2 > ./deleted_files.lst
   else
            current=$(git rev-parse --abbrev-ref HEAD)
            if [ "$current" == "master" ];then
                  git diff --diff-filter=d --name-only $1  $2 > ./changed_files.lst &&
                  git diff --diff-filter=D --name-only $1  $2 > ./deleted_files.lst
            else
                  git diff --diff-filter=d --name-only origin/master...$2  > ./changed_files.lst &&
                  git diff --diff-filter=D --name-only origin/master...$2  > ./deleted_files.lst
            fi
   fi        
}

## Derive Product Name

derive_productName () {
while IFS="" read -r p || [ -n "$p" ]
do
  echo "Printing Each Line"
  echo "line value:"$p
  #printf '%s\n' "$p"
  if ([[ $p == *"products/"* ]]); then
      echo "inside product"
      filePath=$(echo "$p" | xargs)
      product_name="$(echo "$filePath" | cut -d'/' -f2)"
      echo "inside product:" $product_name
      echo "PRODUCT_NAME=$product_name" >> $GITHUB_OUTPUT
  fi
done < ./changed_files.lst
}

commitMessage="$(echo "$3"|tr -d '\n')"
echo "commit message : $commitMessage"
if [[ "$commitMessage" == *"BYAPIM"* ]]; then
   commit_message=''
   deploy_environment=''
   deploy_environments="$(echo "$(echo "$(echo "$commitMessage" | cut -d'[' -f2)" | cut -d']' -f1)" | cut -d'-' -f3)"
   echo $deploy_environments
   if [[ "" = "$deploy_environments" ]]; then
      deploy_environment='dev'
      echo "DEPLOY_ENVIRONMENT=dev" >> $GITHUB_OUTPUT
   else
      IFS=', ' read -r -a array <<< "$deploy_environments"
      echo "environment array:"
      echo "${array[@]}"
      arraySize="${#array[@]}"
      echo "size of array: $arraySize"
        if [ $arraySize = 1 ]; then
          echo "array size is 1"
          deploy_environment=$deploy_environments
          echo "API Deploy Envrionment: $deploy_environment"
          echo "DEPLOY_ENVIRONMENT=$deploy_environment" >> $GITHUB_OUTPUT
          echo "DEPLOY_ENVIRONMENT_EU=$deploy_environment" >> $GITHUB_OUTPUT
          echo "DEPLOY_ENVIRONMENT_APAC=$deploy_environment" >> $GITHUB_OUTPUT
        else
          echo "array size more than 1"
            for env in "${array[@]}"
            do
                #echo "environment is: $env"
                if [[ "$env" = 'prd_eu' ]]; then
                  deploy_environment=$env
                  echo "API EU Deploy Envrionment: $deploy_environment"
                  echo "DEPLOY_ENVIRONMENT_EU=$deploy_environment" >> $GITHUB_OUTPUT
                fi
                if [[ "$env" = 'prd_apac' ]]; then
                  deploy_environment=$env
                  echo "API APAC Deploy Envrionment: $deploy_environment"
                  echo "DEPLOY_ENVIRONMENT_APAC=$deploy_environment" >> $GITHUB_OUTPUT
                fi
                if [[ "$env" = 'prd' ]]; then
                  deploy_environment=$env
                  echo "API Deploy Envrionment: $deploy_environment"
                  echo "DEPLOY_ENVIRONMENT=$deploy_environment" >> $GITHUB_OUTPUT
                fi
                if [[ "$env" = 'prodstage' ]]; then
                  deploy_environment=$env
                  echo "API Deploy Envrionment: $deploy_environment"
                  echo "DEPLOY_ENVIRONMENT=$deploy_environment" >> $GITHUB_OUTPUT
                fi
            done
        fi
   fi

      if [[ "sbx" = "$deploy_environment" || "dev" = "$deploy_environment" ]]; then
         echo "inside sbx or dev loop"
         detect_changes $1 $2
         #calling product derive function
         derive_productName
         if [ "sbx" = "$deploy_environment" ]; then
            commit_message="[BYAPIM-deploy-dev-$2]"
         fi
         if [ "dev" = "$deploy_environment" ]; then
            commit_message="[BYAPIM-deploy-tst-$2]"
         fi
         echo "COMMIT_MESSAGE=$commit_message" >> $GITHUB_ENV
      else
         deploy_sha="$(echo "$(echo "$(echo "$commitMessage" | cut -d'[' -f2)" | cut -d']' -f1)" | cut -d'-' -f4)"
         echo $deploy_sha
         envValCommand=".[] | select(.body | contains(\"changes\")).body | fromjson"
         resoutput=$( curl -sL -X GET -d @- \
               -H "Content-Type: application/json" \
               -H "Authorization: token $4" \
               "https://api.github.com/repos/$5/commits/$deploy_sha/comments" | jq --raw-output -c "$envValCommand")

         echo "comments body: $resoutput"
         prevDeployEnv=$(echo "$resoutput" | jq --raw-output .env)
         envValidation='fail'
         if [ "tst" = "$deploy_environment" ]; then
           envValidation='success'
           commit_message="[BYAPIM-deploy-prd-$2]"
#            if [ "dev" = "$prevDeployEnv" ]; then
#               commit_message="[BYAPIM-deploy-prd-$2]"
#               envValidation='success'
#            else
#               echo "::set-output name=VALIDATION_RESULT::Validation Failed, Cannot Skip Lower Environment Deployment"
#            fi
         fi
        if [[ "$deploy_environment" =~ "prd" ]]; then
          envValidation='success'
#            if [ "tst" = "$prevDeployEnv" ]; then
#               envValidation='success'
#            else
#               echo "::set-output name=VALIDATION_RESULT::Validation Failed, Cannot Skip Lower Environment Deployment"
#            fi
         fi
         echo "COMMIT_MESSAGE=$commit_message" >> $GITHUB_ENV
         if [ "success" = "$envValidation" ]; then
            changesVar=$(echo "$resoutput" | jq --raw-output .changes)
            echo "changes are: $changesVar"
            echo "$changesVar" | tr "," "\n" > changed_files.lst
            sed -i 's/^/\products\//g' changed_files.lst
            sed -i 's/$/\/metadata.yaml/g' changed_files.lst
            #calling product derive function
            derive_productName
         fi
      fi
else
   detect_changes $1 $2
   #calling product derive function
   derive_productName
   deploy_environment='dev'
   echo "DEPLOY_ENVIRONMENT=dev" >> $GITHUB_OUTPUT
   commit_message="[BYAPIM-deploy-tst-$2]"
   echo "COMMIT_MESSAGE=$commit_message" >> $GITHUB_ENV
fi

##Retrieve Environment Service URL
envServiceUrl=$(grep -A1 'envService:' "./.github/config/apim_$deploy_environment.yaml" | tail -n1)
envServiceUrl=${envServiceUrl//*url: /}
echo "Env Service: $envServiceUrl"
echo "ENV_SVC_URL=$envServiceUrl" >> $GITHUB_ENV

while IFS="" read -r p || [ -n "$p" ]
do
  echo "Printing Each Line"
  #printf '%s\n' "$p"
  if ([[ $p == *"products/"* ]]); then
     dltfilePath=$(echo "$p" | xargs)
     IFS='/' read -r -a dltfileArray <<< "$dltfilePath"
     dltfileArrSize=$(echo "${#dltfileArray[@]}")
     echo "arraySize: $dltfileArrSize"
        if [ "$dltfileArrSize" = 3 ]; then
            echo "Inside Array loop"
            errorMessage="X Validation Failed File got deleted on Product: $dltfilePath"
            echo "VALIDATION_RESULT=$errorMessage" >> $GITHUB_OUTPUT
            product_name="$(echo "$dltfilePath" | cut -d'/' -f2)"
            echo "inside delete product:" $product_name
            echo "PRODUCT_NAME=$product_name" >> $GITHUB_OUTPUT
        fi
  fi
done < ./deleted_files.lst