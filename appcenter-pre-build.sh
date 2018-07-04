COMMIT_MESSAGE=$(git log -1 --pretty=%B)
COMMIT_HASH="$BUILD_SOURCEVERSION"
BUILD_ANDROID="0"
BUILD_IOS="0"
LAST_ANDROID=$(git log --grep='\[release android\]' -1 | grep -o -E -e "[0-9a-f]{40}")
LAST_IOS=$(git log --grep='\[release ios\]' -1 | grep -o -E -e "[0-9a-f]{40}")

if [[ "$LAST_ANDROID" == "" ]]; then
  echo "Warning: No previous [Android] build"
  LAST_ANDROID=$(git log --max-parents=0 HEAD | grep -o -E -e "[0-9a-f]{40}")
fi

if [[ "$LAST_IOS" == "" ]]; then
  echo "Warning: No previous [iOS] build"
  LAST_IOS=$(git log --max-parents=0 HEAD | grep -o -E -e "[0-9a-f]{40}")
fi

TRIGGER_ANDROID=$(git rev-list $LAST_ANDROID..$COMMIT_HASH | xargs -L1 git diff-tree --no-commit-id --name-only -r | grep "^android")
TRIGGER_IOS=$(git rev-list $LAST_IOS..$COMMIT_HASH | xargs -L1 git diff-tree --no-commit-id --name-only -r | grep "^ios")

if [ ! -z "$GOOGLE_SERVICES_JSON" ]; then
  echo $GOOGLE_SERVICES_JSON | base64 --decode > "$APPCENTER_SOURCE_DIRECTORY/android/app/google-services.json"
fi

if [ ! -z "$GOOGLE_SERVICES_PLIST" ]; then
  echo $GOOGLE_SERVICES_PLIST | base64 --decode > "$APPCENTER_SOURCE_DIRECTORY/ios/Hekla/GoogleService-Info.plist"
fi

for KEY in $(cat .env_example | egrep "^[A-Za-z]+" | sed 's/\"/\\\"/g' | sed -n 's|\(.*\)=\(.*\)|\1|p'); do
  echo "$KEY=$(printf '%s\n' "${!KEY}")" >> "$APPCENTER_SOURCE_DIRECTORY/.env"
done

source "$APPCENTER_SOURCE_DIRECTORY/scripts/build-env.sh"

if [ ! -z "$IOS_CODEPUSH_APPID"]; then
  if [[ "$TRIGGER_IOS" != "" ]]; then
    cd ios
    fastlane bump_version
    cd -
  else
    npm install -g code-push
    code-push login --accessKey $CODEPUSH_ACCESS_KEY
    code-push release-react $IOS_CODEPUSH_APPID ios --outputDir ./build --plistFile ./ios/Hekla/Info.plist --description "$COMMIT_MESSAGE"
    sentry-cli react-native codepush $IOS_CODEPUSH_APPID ios ./build --bundle-id $IOS_BUNDLE_ID
    curl -X PATCH "https://api.appcenter.ms/v0.1/apps/$IOS_CODEPUSH_APPID/builds/$APPCENTER_BUILD_ID" -H "accept: application/json" -H "X-API-Token: $APPCENTER_API_KEY" -H "Content-Type: application/json" -d "{ \"status\": \"cancelling\" }"
  fi
fi

if [ ! -z "$ANDROID_CODEPUSH_APPID" ]; then
  if [[ "$TRIGGER_ANDROID" != "" ]]; then
    cd android
    fastlane bump_version
    cd -
  else
    npm install -g code-push
    code-push login --accessKey $CODEPUSH_ACCESS_KEY
    code-push release-react $ANDROID_CODEPUSH_APPID android --outputDir build --description "$COMMIT_MESSAGE"
    sentry-cli react-native codepush $ANDROID_CODEPUSH_APPID android ./build --bundle-id $ANDROID_BUNDLE_ID
    curl -X PATCH "https://api.appcenter.ms/v0.1/apps/$ANDROID_CODEPUSH_APPID/builds/$APPCENTER_BUILD_ID" -H "accept: application/json" -H "X-API-Token: $APPCENTER_API_KEY" -H "Content-Type: application/json" -d "{ \"status\": \"cancelling\" }"
  fi
fi
