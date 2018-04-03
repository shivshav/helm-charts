#!/bin/bash

# only execute this script as part of the pipeline.
[ -z "$CI" ] && echo "missing ci environment variable" && exit 2
# Verify that the semver for the chart was increased
semvercompare() {
  printf "\nChecking the Chart version has increased for the chart at ${1}\n"

  # Checkout the Chart.yaml file on master to read the version for comparison
  # Sending the output to a file and the error to /dev/null so that these
  # messages do not clutter up the end user output
  $(git show k8s/master:$1/Chart.yaml 1> /tmp/Chart.yaml 2> /dev/null)

  ## If the chart is new git cannot checkout the chart. In that case return
  if [ $? -ne 0 ]; then
    echo "Unable to find Chart on master. New chart detected."
    return
  fi

  semvercompareOldVer=`yaml r /tmp/Chart.yaml version`
  semvercompareNewVer=`yaml r $1/Chart.yaml version`

  # Pre-releases may not be API compatible. So, when tools compare versions
  # they often skip pre-releases. vert can force looking at pre-releases by
  # adding a dash on the end followed by pre-release. -0 on the end will force
  # looking for all valid pre-releases since a prerelease cannot start with a 0.
  # For example, 1.2.3-0 will include looking for pre-releases.
  local ret
  local out
  if [[ $semvercompareOldVer == *"-"* ]]; then  # Found the - to denote it has a pre-release
    out=$(vert ">$semvercompareOldVer" $semvercompareNewVer)
    ret=$?
  else
    # No pre-release was found so we increment the patch version and attach a
    # -0 to enable pre-releases being found.
    local ov=( ${semvercompareOldVer//./ } )  # Turn the version into an array
    ((ov[2]+=1))                  # Increment the patch release
    out=$(vert ">${ov[0]}.${ov[1]}.${ov[2]}-0" $semvercompareNewVer)
    ret=$?
  fi

  if [ $ret -ne 0 ]; then
    echo "Error please increment the new chart version to be greater than the existing version of $semvercompareOldVer"
    exitCode=1
  else
    echo "New higher version $semvercompareNewVer found"
  fi

  # Clean up
  rm /tmp/Chart.yaml
}

echo "Installing dependencies..."
apt-get -qq update && apt-get -qq install -y git wget

mkdir bin
export PATH=$PATH:$HOME/bin
wget -q -o /dev/null https://github.com/Masterminds/vert/releases/download/v0.1.0/vert-v0.1.0-linux-amd64 -O ./bin/vert
chmod +x vert

if [[ -z ${1} ]]; then
  git remote add k8s https://github.com/shivshav/helm-charts
  git fetch k8s master
  CHANGED_FOLDERS=`git diff --find-renames --name-only $(git merge-base k8s/master HEAD) charts | awk -F/ '{print $1"/"$2}' | uniq`
else
  CHANGED_FOLDERS=( ${1} "" )
fi

# Exit early if no charts have changed
if [ -z "$CHANGED_FOLDERS" ]; then
  echo "No changes to charts found"
  exit 0
fi

for directory in ${CHANGED_FOLDERS}; do
  #printf "\nRunning helm dep build on the chart at ${directory}\n"
  #run helm dep build ${directory}

  #printf "\nRunning helm lint on the chart at ${directory}\n"
  #run helm lint ${directory}

  #yamllinter ${directory}

  #validate_chart_yaml ${directory}

  semvercompare ${directory}

  # Check for the existence of the NOTES.txt file. This is required for charts
  # in this repo.
  #if [ ! -f ${directory}/templates/NOTES.txt ]; then
  #  echo "Error NOTES.txt template not found. Please create one."
  #  echo "For more information see https://docs.helm.sh/developing_charts/#chart-license-readme-and-notes"
  #  exitCode=1
  #fi

done

exit $exitCode
