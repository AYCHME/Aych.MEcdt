#!/bin/bash
set -eo pipefail
. ./.cicd/helpers/general.sh
export DOCKERIZATION=false
TEST="ctest -j$JOBS -L unit_tests -V -T Test"
[[ $TRAVIS != true ]] && buildkite-agent artifact download build.tar.gz . --step "$PLATFORM_FULL_NAME - Build"
. ./.cicd/helpers/populate-template-and-hash.sh '<!-- DAC ENV'
if [[ $(uname) == 'Darwin' ]]; then # macOS
    if [[ $TRAVIS == true ]]; then
        . /tmp/$POPULATED_FILE_NAME
        cp -rfp $(pwd) $EOSIO_CDT_LOCATION
        cd $EOSIO_CDT_LOCATION
        tar -xzf build.tar.gz
    fi
    set +e # defer error handling to end
    "$TEST"
    EXIT_STATUS=$?
else # Linux
    ARGS="--rm --init -v $(pwd):$(pwd) $(buildkite-intrinsics) -e JOBS"
    . $HELPERS_DIR/populate-template-and-hash.sh -h # Obtain the hash from the populated template 
    echo "cp -rfp $(pwd) \$EOSIO_CDT_LOCATION && cd \$EOSIO_CDT_LOCATION" >> /tmp/$POPULATED_FILE_NAME # We don't need to clone twice
    [[ $TRAVIS != true ]] && echo "tar -xzf build.tar.gz" >> /tmp/$POPULATED_FILE_NAME
    echo "$TEST" >> /tmp/$POPULATED_FILE_NAME
    echo "cp -rfp \$EOSIO_CDT_LOCATION/build $(pwd)" >> /tmp/$POPULATED_FILE_NAME
    TEST_COMMANDS="cd $(pwd) && ./$POPULATED_FILE_NAME"
    cat /tmp/$POPULATED_FILE_NAME
    mv /tmp/$POPULATED_FILE_NAME ./$POPULATED_FILE_NAME
    echo "$ docker run $ARGS $FULL_TAG bash -c \"$TEST_COMMANDS\""
    set +e # defer error handling to end
    eval docker run $ARGS $FULL_TAG bash -c \"$TEST_COMMANDS\"
    EXIT_STATUS=$?
fi
# buildkite
if [[ $BUILDKITE == true ]]; then
    cd build
    # upload artifacts
    echo '+++ :arrow_up: Uploading Artifacts'
    echo 'Compressing core dumps...'
    [[ $((`ls -1 core.* 2>/dev/null | wc -l`)) != 0 ]] && tar czf core.tar.gz core.* || : # collect core dumps
    echo 'Exporting xUnit XML'
    mv -f ./Testing/$(ls ./Testing/ | grep '2' | tail -n 1)/Test.xml test-results.xml
    echo 'Uploading artifacts'
    [[ -f config.ini ]] && buildkite-agent artifact upload config.ini
    [[ -f core.tar.gz ]] && buildkite-agent artifact upload core.tar.gz
    [[ -f genesis.json ]] && buildkite-agent artifact upload genesis.json
    [[ -f mongod.log ]] && buildkite-agent artifact upload mongod.log
    buildkite-agent artifact upload test-results.xml
    echo 'Done uploading artifacts.'
fi
# re-throw
if [[ $EXIT_STATUS != 0 ]]; then
    echo "Failing due to non-zero exit status from ctest: $EXIT_STATUS"
    exit $EXIT_STATUS
fi