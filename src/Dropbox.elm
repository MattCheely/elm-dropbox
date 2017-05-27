module Dropbox
    exposing
        ( AuthorizeRequest
        , Dimensions
        , DownloadRequest
        , DownloadResponse
        , FileSharingInfo
        , GpsCoordinates
        , MediaInfo
        , MediaMetadata
        , PhotoMetadata
        , PropertyGroup
        , UploadRequest
        , UploadResponse
        , UserAuth
        , VideoMetadata
        , WriteMode(..)
        , authFromLocation
        , authorizationUrl
        , authorize
        , download
        , program
        , tokenRevoke
        , upload
        )

{-|


## Dropbox API

See the official Dropbox documentation at
<https://www.dropbox.com/developers/documentation/http/documentation>

@docs program


### Authorization

@docs AuthorizeRequest, authFromLocation, authorize, authorizationUrl, UserAuth


### Auth

@docs tokenRevoke


### Files

@docs download, DownloadRequest, DownloadResponse
@docs upload, UploadRequest, WriteMode, UploadResponse, MediaInfo, MediaMetadata, PhotoMetadata, VideoMetadata, Dimensions, GpsCoordinates, FileSharingInfo, PropertyGroup

-}

import Date exposing (Date)
import Date.Format
import Dict exposing (Dict)
import Html exposing (Html)
import Http
import Json.Decode
import Json.Decode.Extra
import Json.Decode.Pipeline as Pipeline
import Json.Encode
import Navigation
import Update.Extra


{-| Request parameters for Dropbox OAuth 2.0 authorization requests.

See <https://www.dropbox.com/developers/documentation/http/documentation#oauth2-authorize>

-}
type alias AuthorizeRequest =
    { clientId : String
    , redirectUri : String
    }


{-| Create a `AuthorizeRequest` from a `Navigation.Location`. This can be used
with `Navigation.program` to automatically generate the redirectUri from the
current page's URL.
-}
authFromLocation : String -> Navigation.Location -> AuthorizeRequest
authFromLocation clientId location =
    { clientId = clientId
    , redirectUri =
        location.protocol
            ++ "//"
            ++ location.host
            ++ location.pathname
    }


{-| Return value of the `authorize` endpoint, which is the data Dropbox returns via
the redirect URL.

You can get the `AuthorizeResponse` by using `Dropbox.program`,
or by using `parseAuth` if you need to manually parse the redirect URL.

See <https://www.dropbox.com/developers/documentation/http/documentation#oauth2-authorize>

-}
type alias AuthorizeResponse =
    { accessToken : String
    , tokenType : String
    , uid : String
    , accountId : String
    }


{-| The Dropbox OAuth 2.0 authorization URL.
Typically you will just want to use `authorize` instead,
which will initiate the authorization.

See <https://www.dropbox.com/developers/reference/oauth-guide>

-}
authorizationUrl : AuthorizeRequest -> String
authorizationUrl request =
    String.concat
        [ "https://www.dropbox.com/oauth2/authorize"
        , "?"
        , "response_type=token"
        , "&"
        , "client_id="
        , request.clientId
        , "&"
        , "redirect_uri="
        , request.redirectUri
        ]


{-| <https://www.dropbox.com/developers/documentation/http/documentation#oauth2-authorize>
-}
authorize : AuthorizeRequest -> Cmd msg
authorize request =
    Navigation.load <|
        authorizationUrl request


parseAuth : Navigation.Location -> Maybe AuthorizeResponse
parseAuth location =
    let
        isKeyValue list =
            case list of
                [ k, v ] ->
                    Just ( k, v )

                _ ->
                    Nothing

        makeAuth dict =
            Maybe.map4 AuthorizeResponse
                (Dict.get "access_token" dict)
                (Dict.get "token_type" dict)
                (Dict.get "uid" dict)
                (Dict.get "account_id" dict)
    in
    case String.uncons location.hash of
        Just ( '#', hash ) ->
            hash
                |> String.split "&"
                |> List.map (String.split "=")
                |> List.filterMap isKeyValue
                |> Dict.fromList
                |> makeAuth

        _ ->
            Nothing


{-| A user authentication token that can be used to authenticate API calls

See <https://www.dropbox.com/developers/reference/auth-types#user>

-}
type UserAuth
    = Bearer String


authorization : AuthorizeResponse -> Result String UserAuth
authorization response =
    case response.tokenType of
        "bearer" ->
            Ok <| Bearer response.accessToken

        _ ->
            Err ("Unknown token_type: " ++ response.tokenType)


authHeader : UserAuth -> Http.Header
authHeader auth =
    case auth of
        Bearer accessToken ->
            Http.header "Authorization" ("Bearer " ++ accessToken)


{-| Disables the access token used to authenticate the call.

See <https://www.dropbox.com/developers/documentation/http/documentation#auth-token-revoke>

-}
tokenRevoke : UserAuth -> Http.Request ()
tokenRevoke auth =
    let
        url =
            "https://api.dropboxapi.com/2/auth/token/revoke"

        parse response =
            Ok ()
    in
    Http.request
        { method = "POST"
        , headers =
            [ authHeader auth
            ]
        , url = url
        , body = Http.emptyBody
        , expect = Http.expectStringResponse parse
        , timeout = Nothing
        , withCredentials = False
        }


{-| Request parameteres for `download`
-}
type alias DownloadRequest =
    { filename : String
    }


{-| Return value for `download`
-}
type alias DownloadResponse =
    { content : String
    }


{-| Download a file from a user's Dropbox.

See <https://www.dropbox.com/developers/documentation/http/documentation#files-download>

-}
download : UserAuth -> DownloadRequest -> Http.Request DownloadResponse
download auth info =
    let
        url =
            "https://content.dropboxapi.com/2/files/download"

        parse response =
            Ok { content = response.body }

        dropboxArg =
            Json.Encode.encode 0 <|
                Json.Encode.object
                    [ ( "path", Json.Encode.string info.filename ) ]
    in
    Http.request
        { method = "POST"
        , headers =
            [ authHeader auth
            , Http.header "Dropbox-API-Arg" dropboxArg
            ]
        , url = url
        , body = Http.emptyBody
        , expect = Http.expectStringResponse parse
        , timeout = Nothing
        , withCredentials = False
        }


{-| Your intent when writing a file to some path.
See <https://www.dropbox.com/developers/documentation/http/documentation#files-upload>
-}
type WriteMode
    = Add
    | Overwrite
    | Update String


encodeWriteModel : WriteMode -> Json.Encode.Value
encodeWriteModel mode =
    case mode of
        Add ->
            Json.Encode.object [ ( ".tag", Json.Encode.string "add" ) ]

        Overwrite ->
            Json.Encode.object [ ( ".tag", Json.Encode.string "overwrite" ) ]

        Update rev ->
            Json.Encode.object
                [ ( ".tag", Json.Encode.string "update" )
                , ( "update", Json.Encode.string rev )
                ]


{-| Request parameters for `upload`
-}
type alias UploadRequest =
    { path : String
    , mode : WriteMode
    , autorename : Bool
    , clientModified : Maybe Date
    , mute : Bool
    , content : String
    }


{-| Additional information if the file is a photo or video.

See <https://www.dropbox.com/developers/documentation/http/documentation#files-upload>

-}
type MediaInfo
    = Pending
    | Metadata MediaMetadata


decodeMediaInfo : Json.Decode.Decoder MediaInfo
decodeMediaInfo =
    -- TODO
    Json.Decode.succeed Pending


{-| Metadata for a photo or video.

See <https://www.dropbox.com/developers/documentation/http/documentation#files-upload>

-}
type MediaMetadata
    = Photo PhotoMetadata
    | Video VideoMetadata


{-| Metadata for a photo.

See <https://www.dropbox.com/developers/documentation/http/documentation#files-upload>

-}
type alias PhotoMetadata =
    { dimensions : Maybe Dimensions
    , location : Maybe GpsCoordinates
    , timeTaken : Maybe Date
    }


{-| Metadata for a video.

See <https://www.dropbox.com/developers/documentation/http/documentation#files-upload>

**WARNING**: elm-dropbox may give the incorrect values for `duration`,
since Elm currently does not provide a way to parse and represent 64-bit integers.

-}
type alias VideoMetadata =
    { dimensions : Maybe Dimensions
    , location : Maybe GpsCoordinates
    , timeTaken : Maybe Date
    , duration : Maybe Int -- XXX: should be UInt64
    }


{-| Dimensions for a photo or video.

See <https://www.dropbox.com/developers/documentation/http/documentation#files-upload>

**WARNING**: elm-dropbox may give the incorrect values,
since Elm currently does not provide a way to parse and represent 64-bit integers.

-}
type alias Dimensions =
    { height : Int -- XXX: should be UInt64
    , width : Int -- XXX: should be UInt64
    }


{-| The GPS coordinate of the photo/video.

See <https://www.dropbox.com/developers/documentation/http/documentation#files-upload>

-}
type alias GpsCoordinates =
    { latitude : Float
    , longitude : Float
    }


{-| Sharing info for a file which is contained by a shared folder.

See <https://www.dropbox.com/developers/documentation/http/documentation#files-upload>

-}
type alias FileSharingInfo =
    { readOnly : Bool
    , parentSharedFolderId : String
    , modifiedBy : Maybe String
    }


decodeFileSharingInfo : Json.Decode.Decoder FileSharingInfo
decodeFileSharingInfo =
    Pipeline.decode FileSharingInfo
        |> Pipeline.required "read_only" Json.Decode.bool
        |> Pipeline.required "parent_shared_folder_id" Json.Decode.string
        |> Pipeline.optional "modified_by" (Json.Decode.nullable Json.Decode.string) Nothing


{-| Collection of custom properties in filled property templates.

See <https://www.dropbox.com/developers/documentation/http/documentation#files-upload>

-}
type alias PropertyGroup =
    { templateId : String
    , fields : Dict String String
    }


decodePropertyGroup : Json.Decode.Decoder PropertyGroup
decodePropertyGroup =
    let
        decodeField =
            Json.Decode.map2 (,)
                (Json.Decode.field "name" Json.Decode.string)
                (Json.Decode.field "value" Json.Decode.string)
    in
    Pipeline.decode PropertyGroup
        |> Pipeline.required "template_id" Json.Decode.string
        |> Pipeline.required "fields" (Json.Decode.map Dict.fromList <| Json.Decode.list decodeField)


{-| Return value for `upload`

**WARNING**: elm-dropbox may give the incorrect values for `size`,
since Elm currently does not provide a way to parse and represent 64-bit integers.

-}
type alias UploadResponse =
    { name : String
    , id : String
    , clientModified : Date
    , serverModified : Date
    , rev : String
    , size : Int -- XXX: should be UInt64
    , pathLower : Maybe String
    , pathDisplay : Maybe String
    , parentSharedFolderId : Maybe String
    , mediaInfo : Maybe MediaInfo
    , sharingInfo : Maybe FileSharingInfo
    , propertyGroups : Maybe (List PropertyGroup)
    , hasExplicitSharedMembers : Maybe Bool
    , contentHash : Maybe String
    }


decodeUploadResponse : Json.Decode.Decoder UploadResponse
decodeUploadResponse =
    Pipeline.decode UploadResponse
        |> Pipeline.required "name" Json.Decode.string
        |> Pipeline.required "id" Json.Decode.string
        |> Pipeline.required "client_modified" Json.Decode.Extra.date
        |> Pipeline.required "server_modified" Json.Decode.Extra.date
        |> Pipeline.required "rev" Json.Decode.string
        |> Pipeline.required "size" Json.Decode.int
        |> Pipeline.optional "path_lower" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "path_display" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "parent_shared_folder_id" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Pipeline.optional "media_info" (Json.Decode.nullable decodeMediaInfo) Nothing
        |> Pipeline.optional "sharing_info" (Json.Decode.nullable decodeFileSharingInfo) Nothing
        |> Pipeline.optional "property_groups" (Json.Decode.nullable <| Json.Decode.list decodePropertyGroup) Nothing
        |> Pipeline.optional "has_explicit_shared_members" (Json.Decode.nullable Json.Decode.bool) Nothing
        |> Pipeline.optional "content_hash" (Json.Decode.nullable Json.Decode.string) Nothing


{-| Create a new file with the contents provided in the request.

See <https://www.dropbox.com/developers/documentation/http/documentation#files-upload>

-}
upload : UserAuth -> UploadRequest -> Http.Request UploadResponse
upload auth info =
    let
        url =
            "https://content.dropboxapi.com/2/files/upload"

        body =
            Http.stringBody "application/octet-stream" info.content

        decoder =
            decodeUploadResponse

        dropboxArg =
            Json.Encode.encode 0 <|
                Json.Encode.object <|
                    List.filterMap identity
                        [ Just ( "path", Json.Encode.string info.path )
                        , Just ( "mode", encodeWriteModel info.mode )
                        , Just ( "autorename", Json.Encode.bool info.autorename )
                        , info.clientModified
                            |> Maybe.map Date.Format.formatISO8601
                            |> Maybe.map Json.Encode.string
                            |> Maybe.map ((,) "client_modified")
                        , Just ( "mute", Json.Encode.bool info.mute )
                        ]
    in
    Http.request
        { method = "POST"
        , headers =
            [ authHeader auth
            , Http.header "Dropbox-API-Arg" dropboxArg
            ]
        , url = url
        , body = body
        , expect = Http.expectJson decoder
        , timeout = Nothing
        , withCredentials = False
        }


{-| This provides the simplest way to integrate Dropbox authentication.
Using `Dropbox.program` will handle parsing the authentication response from the
authentication redirect so that you don't have to do it manually.
-}
program :
    { init : Navigation.Location -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , view : model -> Html msg
    , onAuth : Result String UserAuth -> msg
    }
    -> Program Never model (Maybe msg)
program config =
    Navigation.program (always Nothing)
        { init =
            \location ->
                case parseAuth location of
                    Nothing ->
                        config.init location
                            |> Update.Extra.mapCmd Just

                    Just response ->
                        config.init location
                            |> Update.Extra.andThen
                                config.update
                                (config.onAuth <| authorization <| response)
                            |> Update.Extra.mapCmd Just
        , update =
            \msg model ->
                case msg of
                    Nothing ->
                        ( model, Cmd.none )

                    Just m ->
                        config.update m model
                            |> Update.Extra.mapCmd Just
        , subscriptions = \_ -> Sub.none
        , view = config.view >> Html.map Just
        }
