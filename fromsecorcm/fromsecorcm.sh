#!/bin/bash

set -eu

usage() {
cat << EOF
fromsecorcm is a Plugin to get values from secrets or configmaps before running helm.

In your templates set the var as usually, e.g:

    username: {{ .Values.fromsecorcm.myvalue2 | b64enc | quote }}

and create at your chart root directory a file named as:

    fromsecorcm.yaml

In there you will put the values you want to be pulled from secrets or configmaps:

    fromsecorcm:
      myvalue: {{ .Secret.mysecret.password }}
      myvalue2: {{ .Configmap.mycm.username }}

The first one will pull the value from a secret called mysecret and will use the key password.

The second one will pull the value from a confimap called mycm using the key username.

EOF
}

# Check vars
if [[ $# < 1 ]]; then
  usage
  exit 1
fi

# Is a help request?
if [ "$1" = "-h" ] || [ "$1" = "--help" ];
then
  usage
  exit 0
fi

PARAMS="$@"

# Getting templates dir (should come as last param)
BASEDIR=$(echo "$@" | awk '{ print $NF }')
if [ "$BASEDIR" = "." ];
then
  BASEDIR="./"
fi

TEMPLATES=$BASEDIR"templates/"
VALUESFILE=$BASEDIR"fromsecorcm.yaml"
# Checking values file
if [ ! -f $VALUESFILE ];
then
  echo "Values file not found at $VALUESFILE"
  usage
  exit 1
fi
# Check template files
if [ ! -e $TEMPLATES ];
then
  echo "Template dir does not exist!"
  usage
  exit 1
fi

# Create a working copy of values
VALUESFILEWIP=$VALUESFILE".wip"
cp $VALUESFILE $VALUESFILEWIP

# Get namespace if any
NAMESPACE=$(echo $@ | sed -e 's/.*\(--namespace\|-n\)\(\s\+\|=\)\([-a-z]\+\).*/\3/')

if [ "$NAMESPACE" = "$PARAMS" ];
then
  NAMESPACE=""
fi

# Loop through file looking for replacement vars
REPVAR=$(grep -o '{{[[:space:]]*.\(Secret\|Configmap\).[-a-z]*.[-a-z]*[[:space:]]*}}' $VALUESFILEWIP | wc -l)
until [ "$REPVAR" = "0" ];
do
  # Look for and replace repvars
  REPVARWIP=$(grep -o '{{[[:space:]]*.\(Secret\|Configmap\).[-a-z]*.[-a-z]*[[:space:]]*}}' $VALUESFILEWIP | head -1 )
  KIND=$(echo "$REPVARWIP" | sed -e 's/{{\s*\.\([^\.]\+\).\([^\.]\+\).\([^\.]\+\).\s*}}/\1 \2 \3/g')
  KINDNAME=$(echo "$KIND" | awk '{ print $2 }')
  KINDKEY=$(echo "$KIND" | awk '{ print $3 }')
  KIND=$(echo "$KIND" | awk '{ print $1 }')

  # Check repvar
  if [ -z "KIND" ] || [ -z "$KINDNAME" ] || [ -z "$KINDKEY" ];
  then
    echo "Can not parse repvar $REPVARWIP"
    usage
    rm $VALUESFILEWIP
    exit 1
  fi

  # Check types
  KINDCHECK=$(echo "$KIND"  | sed -e 's/\(Secret\|Configmap\)//')
  if [ ! -z $KINDCHECK ];
  then
    echo "Bad kind: $KIND"
    usage
    rm $VALUESFILEWIP
    exit 1
  fi
  KINDCHECK=$(echo "$KINDNAME"  | sed -e 's/[-a-z]\+//')
  if [ ! -z $KINDCHECK ];
  then
    echo "Bad name: $KINDNAME"
    usage
    rm $VALUESFILEWIP
    exit 1
  fi
  KINDCHECK=$(echo "$KINDKEY"  | sed -e 's/[-a-z]\+//')
  if [ ! -z $KINDCHECK ];
  then
    echo "Bad key: $KINDKEY"
    usage
    rm $VALUESFILEWIP
    exit 1
  fi

  # Get value
  CMD="kubectl get"
  case $KIND in
    Secret)
      CMD=$CMD" secret"
      ;;
    Configmap)
      CMD=$CMD" configmap"
      ;;
    *)
      echo "Can not process kind: $KIND"
      usage
      rm $VALUESFILEWIP
      exit 1
      ;;
  esac
  if [ ! -z "$NAMESPACE" ];
  then
    CMD=$CMD" -n $NAMESPACE"
  fi
    
  CMD=$CMD" $KINDNAME -o yaml"
  ECMD=$CMD' | grep "'$KINDKEY':" | cat'
  VALUE=$(eval $ECMD)
  if [ -z "$VALUE" ];
  then
    echo "Key not found: $REPVARWIP"
    usage
    rm $VALUESFILEWIP
    exit 1
  fi
  VALUEQTY=$(echo "$VALUE" | wc -l)
  if [ ! "$VALUEQTY" = "1" ]
  then
    echo "Bad Key, found more than one: $REPVARWIP"
    usage
    rm $VALUESFILEWIP
    exit 1
  fi
  # value should be "key: value" so let's get the actual value
  VALUEACTUAL=$(echo "$VALUE" | sed -e 's/^\s\+[-a-zA-Z]\+:\s\+\(.\+\)$/\1/')

  if [ "$KIND" = "Secret" ];
  then
    VALUEACTUAL=$(echo "$VALUEACTUAL" | base64 -d)
    #VALUEACTUAL=$(echo "${VALUEACTUAL::-1}")
  fi
  # Now replace the actual value
  CMD="sed -i -e 's/{{\s*\.'$KIND'.'$KINDNAME'.'$KINDKEY'.\s*}}/'$VALUEACTUAL'/g' $VALUESFILEWIP"
  eval $CMD
  REPVAR=$(grep -o '{{[[:space:]]*.\(Secret\|Configmap\).[-a-z]*.[-a-z]*[[:space:]]*}}' $VALUESFILEWIP | wc -l)

done

CMD="$HELM_BIN $@"
CMD="echo '$CMD' | sed -e 's:^\(.\+\)[[:space:]]\([^[:space:]]\+\)$:\1 -f "$VALUESFILEWIP" \2:'"
CMD=$(eval $CMD)
eval $CMD
# Delete wip file
rm $VALUESFILEWIP
exit 0
