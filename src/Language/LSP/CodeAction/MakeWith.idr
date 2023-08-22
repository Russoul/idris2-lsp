module Language.LSP.CodeAction.MakeWith

import Core.Context
import Core.Core
import Core.Env
import Core.Metadata
import Core.UnifyState
import Idris.IDEMode.MakeClause
import Idris.REPL.Opts
import Idris.Resugar
import Idris.Syntax
import Language.JSON
import Language.LSP.CodeAction
import Language.LSP.CodeAction.Utils
import Language.LSP.Message
import Language.LSP.Utils
import Libraries.Data.PosMap
import Parser.Unlit
import Server.Configuration
import Server.Log
import Server.Utils
import TTImp.TTImp

buildCodeAction : Name -> URI -> TextEdit -> CodeAction
buildCodeAction name uri edit =
  MkCodeAction
    { title       = "Make with for hole ?\{show name}"
    , kind        = Just RefactorRewrite
    , diagnostics = Nothing
    , isPreferred = Nothing
    , disabled    = Nothing
    , edit        = Just $ MkWorkspaceEdit
        { changes           = Just (singleton uri [edit])
        , documentChanges   = Nothing
        , changeAnnotations = Nothing
        }
    , command     = Nothing
    , data_       = Nothing
    }

export
makeWithKind : CodeActionKind
makeWithKind = Other "refactor.rewrite.MakeWith"

isAllowed : CodeActionParams -> Bool
isAllowed params =
  maybe True (\filter => (makeWithKind `elem` filter) || (RefactorRewrite `elem` filter)) params.context.only

export
makeWith : Ref LSPConf LSPConfiguration
        => Ref MD Metadata
        => Ref Ctxt Defs
        => Ref UST UState
        => Ref Syn SyntaxInfo
        => Ref ROpts REPLOpts
        => CodeActionParams -> Core (Maybe CodeAction)
makeWith params = do
  let True = isAllowed params
    | False => logI MakeWith "Skipped" >> pure Nothing
  logI MakeWith "Checking for \{show params.textDocument.uri} at \{show params.range}"

  withSingleLine MakeWith params (pure Nothing) $ \line => do
    withSingleCache MakeWith params MakeWith $ do
      nameLocs <- gets MD nameLocMap
      let col = params.range.start.character
      let Just (loc@(_, nstart, nend), name) = findPointInTreeLoc (line, col) nameLocs
        | Nothing => logD MakeWith "No name found at \{show line}:\{show col}}" >> pure Nothing
      logD MakeCase "Found name \{show name}"

      context <- gets Ctxt gamma
      [(_, _, Hole locs _, _)] <- lookupNameBy (\g => (definition g, type g)) name context
        | _ => logD MakeWith "\{show name} is not a metavariable" >> pure Nothing

      logD MakeCase "Found metavariable \{show name}"
      litStyle <- getLitStyle
      Just src <- getSourceLine (line + 1)
        | Nothing => logE MakeWith "Error while fetching the referenced line" >> pure Nothing
      let Right l = unlit litStyle src
        | Left err => logE MakeWith "Invalid literate Idris" >> pure Nothing
      let (markM, _) = isLitLine src
      let with_ = makeWith name l
      let range = MkRange (MkPosition line 0) (MkPosition line (cast (length src) - 1))
      let edit = MkTextEdit range with_

      pure $ Just (cast loc, buildCodeAction name params.textDocument.uri edit)
