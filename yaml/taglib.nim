#            NimYAML - YAML implementation in Nim
#        (c) Copyright 2016 Felix Krause
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.

## ==================
## Module yaml.taglib
## ==================
##
## The taglib API enables you to query real names of tags emitted by the parser
## and create own tags. It also enables you to define tags for types used with
## the serialization API.

import tables, macros, hashes
import data

type
  TagLibrary* = ref object
    ## A ``TagLibrary`` maps tag URIs to ``TagId`` s.
    ##
    ## When `YamlParser <#YamlParser>`_ encounters tags not existing in the
    ## tag library, it will use
    ## `registerUri <#registerUri,TagLibrary,string>`_ to add
    ## the tag to the library.
    ##
    ## You can base your tag library on common tag libraries by initializing
    ## them with `initFailsafeTagLibrary <#initFailsafeTagLibrary>`_,
    ## `initCoreTagLibrary <#initCoreTagLibrary>`_ or
    ## `initExtendedTagLibrary <#initExtendedTagLibrary>`_.
    tags*: Table[string, TagId]
    nextCustomTagId*: TagId

proc initTagLibrary*(): TagLibrary {.raises: [].} =
  ## initializes the ``tags`` table and sets ``nextCustomTagId`` to
  ## ``yFirstCustomTagId``.
  new(result)
  result.tags = initTable[string, TagId]()

  result.nextCustomTagId = yFirstCustomTagId

proc registerUri*(tagLib: TagLibrary, uri: string): TagId {.raises: [].} =
  ## registers a custom tag URI with a ``TagLibrary``. The URI will get
  ## the ``TagId`` ``nextCustomTagId``, which will be incremented.
  tagLib.tags[uri] = tagLib.nextCustomTagId
  result = tagLib.nextCustomTagId
  tagLib.nextCustomTagId = cast[TagId](cast[int](tagLib.nextCustomTagId) + 1)

proc uri*(tagLib: TagLibrary, id: TagId): string {.raises: [KeyError].} =
  ## retrieve the URI a ``TagId`` maps to.
  for iUri, iId in tagLib.tags.pairs:
    if iId == id: return iUri
  raise newException(KeyError, "Unknown tag id: " & $id)

template y(suffix: string): string = yamlTagRepositoryPrefix & suffix
template n(suffix: string): string = nimyamlTagRepositoryPrefix & suffix

proc initFailsafeTagLibrary*(): TagLibrary {.raises: [].} =
  ## Contains only:
  ## - ``!``
  ## - ``?``
  ## - ``!!str``
  ## - ``!!map``
  ## - ``!!seq``
  result = initTagLibrary()
  result.tags["!"] = yTagExclamationMark
  result.tags["?"] = yTagQuestionMark
  result.tags[y"str"] = yTagString
  result.tags[y"seq"] = yTagSequence
  result.tags[y"map"] = yTagMapping

proc initCoreTagLibrary*(): TagLibrary {.raises: [].} =
  ## Contains everything in ``initFailsafeTagLibrary`` plus:
  ## - ``!!null``
  ## - ``!!bool``
  ## - ``!!int``
  ## - ``!!float``
  result = initFailsafeTagLibrary()
  result.tags[y"null"]  = yTagNull
  result.tags[y"bool"]  = yTagBoolean
  result.tags[y"int"]   = yTagInteger
  result.tags[y"float"] = yTagFloat

proc initExtendedTagLibrary*(): TagLibrary {.raises: [].} =
  ## Contains everything from ``initCoreTagLibrary`` plus:
  ## - ``!!omap``
  ## - ``!!pairs``
  ## - ``!!set``
  ## - ``!!binary``
  ## - ``!!merge``
  ## - ``!!timestamp``
  ## - ``!!value``
  ## - ``!!yaml``
  result = initCoreTagLibrary()
  result.tags[y"omap"]      = yTagOrderedMap
  result.tags[y"pairs"]     = yTagPairs
  result.tags[y"binary"]    = yTagBinary
  result.tags[y"merge"]     = yTagMerge
  result.tags[y"timestamp"] = yTagTimestamp
  result.tags[y"value"]     = yTagValue
  result.tags[y"yaml"]      = yTagYaml

proc initSerializationTagLibrary*(): TagLibrary =
  result = initTagLibrary()
  result.tags["!"] = yTagExclamationMark
  result.tags["?"] = yTagQuestionMark
  result.tags[y"str"]        = yTagString
  result.tags[y"null"]       = yTagNull
  result.tags[y"bool"]       = yTagBoolean
  result.tags[y"float"]      = yTagFloat
  result.tags[y"timestamp"]  = yTagTimestamp
  result.tags[y"value"]      = yTagValue
  result.tags[y"binary"]     = yTagBinary
  result.tags[n"field"]      = yTagNimField

var
  serializationTagLibrary* = initSerializationTagLibrary() ## \
    ## contains all local tags that are used for type serialization. Does
    ## not contain any of the specific default tags for sequences or maps,
    ## as those are not suited for Nim's static type system.
    ##
    ## Should not be modified manually. Will be extended by
    ## `serializable <#serializable,stmt,stmt>`_.

var
  nextStaticTagId {.compileTime.} = yFirstStaticTagId ## \
    ## used for generating unique TagIds with ``setTagUri``.
  registeredUris {.compileTime.} = newSeq[string]() ## \
    ## Since Table doesn't really work at compile time, we also store
    ## registered URIs here to be able to generate a static compiler error
    ## when the user tries to register an URI more than once.

template setTagUri*(t: typedesc, uri: string) =
  ## Associate the given uri with a certain type. This uri is used as YAML tag
  ## when loading and dumping values of this type.
  when uri in registeredUris:
    {. fatal: "[NimYAML] URI \"" & uri & "\" registered twice!" .}
  const id {.genSym.} = nextStaticTagId
  static:
    registeredUris.add(uri)
    nextStaticTagId = TagId(int(nextStaticTagId) + 1)
  when nextStaticTagId == yFirstCustomTagId:
    {.fatal: "Too many tags!".}
  serializationTagLibrary.tags[uri] = id
  proc yamlTag*(T: typedesc[t]): TagId {.inline, raises: [].} = id
    ## autogenerated

template setTagUri*(t: typedesc, uri: string, idName: untyped) =
  ## Like `setTagUri <#setTagUri.t,typedesc,string>`_, but lets
  ## you choose a symbol for the `TagId <#TagId>`_ of the uri. This is only
  ## necessary if you want to implement serialization / construction yourself.
  when uri in registeredUris:
    {. fatal: "[NimYAML] URI \"" & uri & "\" registered twice!" .}
  const idName* = nextStaticTagId
  static:
    registeredUris.add(uri)
    nextStaticTagId = TagId(int(nextStaticTagId) + 1)
  when nextStaticTagId == yFirstCustomTagId:
    {.fatal: "Too many tags!".}
  serializationTagLibrary.tags[uri] = idName
  proc yamlTag*(T: typedesc[t]): TagId {.inline, raises: [].} = idName
    ## autogenerated

static:
  # standard YAML tags used by serialization
  registeredUris.add("!")
  registeredUris.add("?")
  registeredUris.add(y"str")
  registeredUris.add(y"null")
  registeredUris.add(y"bool")
  registeredUris.add(y"float")
  registeredUris.add(y"timestamp")
  registeredUris.add(y"value")
  registeredUris.add(y"binary")
  # special tags used by serialization
  registeredUris.add(n"field")

# tags for Nim's standard types
setTagUri(char, n"system:char", yTagNimChar)
setTagUri(int8, n"system:int8", yTagNimInt8)
setTagUri(int16, n"system:int16", yTagNimInt16)
setTagUri(int32, n"system:int32", yTagNimInt32)
setTagUri(int64, n"system:int64", yTagNimInt64)
setTagUri(uint8, n"system:uint8", yTagNimUInt8)
setTagUri(uint16, n"system:uint16", yTagNimUInt16)
setTagUri(uint32, n"system:uint32", yTagNimUInt32)
setTagUri(uint64, n"system:uint64", yTagNimUInt64)
setTagUri(float32, n"system:float32", yTagNimFloat32)
setTagUri(float64, n"system:float64", yTagNimFloat64)

proc nimTag*(suffix: string): string =
  ## prepends NimYAML's tag repository prefix to the given suffix. For example,
  ## ``nimTag("system:char")`` yields ``"tag:nimyaml.org,2016:system:char"``.
  nimyamlTagRepositoryPrefix & suffix
