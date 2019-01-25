#!/bin/bash

# Copyright (c) 2018, WSO2 Inc. (http://wso2.com) All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o xtrace

HOME=`pwd`
TEST_SCRIPT=test.sh

function usage()
{
    echo "
    Usage bash test.sh --input-dir /workspace/data-bucket.....
    Following are the expected input parameters. all of these are optional
    --input-dir       | -i    : input directory for test.sh
    --output-dir      | -o    : output directory for test.sh
    "
}

optspec=":hiom-:"
while getopts "$optspec" optchar; do
    case "${optchar}" in
        -)
            case "${OPTARG}" in
                input-dir)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    INPUT_DIR=$val
                    ;;
                output-dir)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    OUTPUT_DIR=$val
                    ;;
                mvn-opts)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    MAVEN_OPTS=$val
                    ;;
                *)
                    usage
                    if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                        echo "Unknown option --${OPTARG}" >&2
                    fi
                    ;;
            esac;;
        h)
            usage
            exit 2
            ;;
        o)
            OUTPUT_DIR=$val
            ;;
        m)
            MVN_OPTS=$val
            ;;
        i)
            INPUT_DIR=$val
            ;;
        *)
            usage
            if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
                echo "Non-option argument: '-${OPTARG}'" >&2
            fi
            ;;
    esac
done

FILE="${INPUT_DIR}/deployment.properties"
PROP_KEY=sshKeyFileLocation
PROP_TEST_PLAN_ID=testPlanId
PROP_TESTGRID=isTestGrid
PROP_OS=OS
PROP_SERVER_DIR=REMOTE_SERVER_DIR_UNIX
PROP_CLIENT_DIR=COPY_TO_DIR_UNIX
user=''
CONNECT_RETRY_COUNT=20

#=============== Read Deployment.property file ===============================================

key_pem=`grep -w "$PROP_KEY" ${FILE} | cut -d'=' -f2`
testplan_id=`cat ${FILE} | grep -w "$PROP_TEST_PLAN_ID" ${FILE} | cut -d'=' -f2`
isTestGrid=`cat ${FILE} | grep -w "$PROP_TESTGRID" ${FILE} | cut -d'=' -f2`
os=`cat ${FILE} | grep -w "$PROP_OS" ${FILE} | cut -d'=' -f2`
REM_DIR=`grep -w "$PROP_SERVER_DIR" ${FILE} | cut -d'=' -f2`

agent_name=("WSO2APIMInstance1" "WSO2APIMInstance2")
TINKERER_USERNAME='tguser'
TINKERER_PASSWORD='89dfjwe2'

echo "working Directory : ${HOME}"
echo "input directory : ${INPUT_DIR}"
echo "output directory : ${OUTPUT_DIR}"

export DATA_BUCKET_LOCATION=${INPUT_DIR}

#=============== Execute Scenarios ===============================================
mvn clean install -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn \
-fae -B -f pom.xml

#=============== Generate jacoco.exec dump ===========================================
mvn jacoco:dump@pull-test-data -Dapp.host=localhost -Dapp.port=36320 -Dskip.dump=false
ls -l ${HOME}/target

#=============== Copy Surefire Reports ===========================================

#echo "Copying surefire-reports to ${OUTPUT_DIR}"
#mkdir -p ${OUTPUT_DIR}
#find . -name "surefire-reports" -exec cp --parents -r {} ${OUTPUT_DIR} \;

#=============== Code Coverage Report Generation ===========================================

#Get IP address
        echo "Get the IP address of client"
        if [ "${os}" = "Windows" ] ; then
            ipaddress=$(ipconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
        else
            ipaddress=$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
        fi

#Copy files to the client side through tinkerer
if [ "${isTestGrid}" = "Y" ]; then

    for i in "${agent_name[@]}"
    do
        x=0;
        case "${os}" in
            "CentOS")
    	        user=centos ;;
            "RHEL")
    	        user=ec2-user ;;
            "UBUNTU")
                user=ubuntu ;;
        esac

        #Stop the wso2server.sh
        echo "Stop the server in Node ${agent_name[x]}"
        curl -X POST http://ec2-34-232-211-33.compute-1.amazonaws.com:8080/deployment-tinkerer/v0.9/api/test-plan/"${testplan_id}"/agent/"${agent_name[x]}"/operation -H 'content-type: application/json' -d '{"code":"SHELL", "request":"'${REM_DIR}'/bin/wso2server.sh stop"}' -u "${TINKERER_USERNAME}":"${TINKERER_PASSWORD}"
        sleep 10 # wait for 30 second until the server stops

        #Zip the jacoco folder
        echo "Zip the jacoco folder in Node ${agent_name[x]}"
        curl -X POST http://ec2-34-232-211-33.compute-1.amazonaws.com:8080/deployment-tinkerer/v0.9/api/test-plan/"${testplan_id}"/agent/"${agent_name[x]}"/operation -H 'content-type: application/json' -d '{"code":"SHELL", "request":"cd '${REM_DIR}'/repository/logs/jacoco; zip -r jacoco.zip ."}' -u "${TINKERER_USERNAME}":"${TINKERER_PASSWORD}"
        sleep 10

        #Generate key
        echo "Generate a key in Node ${agent_name[x]}"
        curl -X POST http://ec2-34-232-211-33.compute-1.amazonaws.com:8080/deployment-tinkerer/v0.9/api/test-plan/"${testplan_id}"/agent/"${agent_name[x]}"/operation -H 'content-type: application/json' -d '{"code":"SHELL", "request":"mkdir -p '${REM_DIR}'/../keys"}' -u "${TINKERER_USERNAME}":"${TINKERER_PASSWORD}"
        curl -X POST http://ec2-34-232-211-33.compute-1.amazonaws.com:8080/deployment-tinkerer/v0.9/api/test-plan/"${testplan_id}"/agent/"${agent_name[x]}"/operation -H 'content-type: application/json' -d '{"code":"SHELL", "request":"ssh-keygen -b 2048 -t rsa -f '${REM_DIR}'/../keys/deploy.key -q -N \"\""}' -u "${TINKERER_USERNAME}":"${TINKERER_PASSWORD}"

        #Add key to authorized_keys
        echo "Add key of Node ${agent_name[x]} to the authorized_keys in client side"
       `echo "$(curl -X POST http://ec2-34-232-211-33.compute-1.amazonaws.com:8080/deployment-tinkerer/v0.9/api/test-plan/"${testplan_id}"/agent/"${agent_name[x]}"/operation -H 'content-type: application/json' -d '{"code":"SHELL", "request":"cat '${REM_DIR}'/../keys/deploy.key.pub"}' -u "${TINKERER_USERNAME}":"${TINKERER_PASSWORD}")" | sed -nE 's/.*"response":"(.*)","completed.*/\1/p' >> /home/ubuntu/.ssh/authorized_keys`

        #Copy file to client side
        echo "Copy file to the client side from ${agent_name[x]}"
        mkdir -p ${HOME}/code-coverage/resources/instance$((x+1))
        curl -X POST http://ec2-34-232-211-33.compute-1.amazonaws.com:8080/deployment-tinkerer/v0.9/api/test-plan/"${testplan_id}"/agent/"${agent_name[x]}"/operation -H 'content-type: application/json' -d '{"code":"SHELL", "request":"scp -i '${REM_DIR}'/../keys/deploy.key '${REM_DIR}'/repository/logs/jacoco/jacoco.zip '${user}'@'${ipaddress}':'${HOME}'/code-coverage/resources/instance'$((x+1))'"}' -u "${TINKERER_USERNAME}":"${TINKERER_PASSWORD}"
        unzip ${HOME}/code-coverage/resources/instance$((x+1))/jacoco.zip -d ${HOME}/code-coverage/resources/instance$((x+1))/jacoco

        x=$((x+1))
    done
fi


#=============== Execute code-coverage POM and generate coverage reports ===============================
mvn clean install -f ${HOME}/product-scenarios/code-coverage/pom.xml

#=============== Copy Code Coverage Reports ============================================================
cp -r ${HOME}/code-coverage/target/scenario-code-coverage ${OUTPUT_DIR}

#=============== Remove resources folder ===============================================================
rm -rf ${HOME}/code-coverage/resources