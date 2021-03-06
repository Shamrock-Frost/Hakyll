-- | A module that provides different ways to create a @Context@. These
--   functions all use the @HakyllAction@ arrow, so they produce values of the
--   type @HakyllAction () Context@.
module Text.Hakyll.CreateContext
    ( createPage
    , createCustomPage
    , createListing
    , combine
    , combineWithUrl
    ) where

import qualified Data.Map as M
import Control.Arrow (second)
import Control.Monad (liftM2, mplus)
import Control.Applicative ((<$>))

import Text.Hakyll.File
import Text.Hakyll.Context
import Text.Hakyll.HakyllAction
import Text.Hakyll.Render
import Text.Hakyll.Internal.Page

-- | Create a @Context@ from a page file stored on the disk. This is probably
--   the most common way to create a @Context@.
createPage :: FilePath -> HakyllAction () Context
createPage path = HakyllAction
    { actionDependencies = [path]
    , actionUrl          = Just $ toUrl path
    , actionFunction     = const (readPage path)
    }

-- | Create a "custom page" @Context@.
--   
--   The association list given maps keys to values for substitution. Note
--   that as value, you can either give a @String@ or a
--   @HakyllAction () String@. The latter is preferred for more complex data,
--   since it allows dependency checking. A @String@ is obviously more simple
--   to use in some cases.
createCustomPage :: FilePath
                 -> [(String, Either String (HakyllAction () String))]
                 -> HakyllAction () Context
createCustomPage url association = HakyllAction
    { actionDependencies = dataDependencies
    , actionUrl          = Just $ return url
    , actionFunction     = \_ -> M.fromList <$> assoc'
    }
  where
    mtuple (a, b) = b >>= \b' -> return (a, b')
    toHakyllString = second (either return runHakyllAction)
    assoc' = mapM (mtuple . toHakyllString) $ ("url", Left url) : association
    dataDependencies = map snd association >>= getDependencies
    getDependencies (Left _) = []
    getDependencies (Right x) = actionDependencies x

-- | A @createCustomPage@ function specialized in creating listings.
--
--   This function creates a listing of a certain list of @Context@s. Every
--   item in the list is created by applying the given template to every
--   renderable. You can also specify additional context to be included in the
--   @CustomPage@.
createListing :: FilePath                  -- ^ Destination of the page.
              -> [FilePath]                -- ^ Templates to render items with.
              -> [HakyllAction () Context] -- ^ Renderables in the list.
              -> [(String, Either String (HakyllAction () String))]
              -> HakyllAction () Context
createListing url templates renderables additional =
    createCustomPage url context
  where
    context = ("body", Right concatenation) : additional
    concatenation = renderAndConcat templates renderables

-- | Combine two @Context@s. The url will always be taken from the first
--   @Renderable@. Also, if a `$key` is present in both renderables, the
--   value from the first @Context@ will be taken as well.
--
--   You can see this as a this as a @union@ between two mappings.
combine :: HakyllAction () Context -> HakyllAction () Context
        -> HakyllAction () Context
combine x y = HakyllAction
    { actionDependencies = actionDependencies x ++ actionDependencies y
    , actionUrl          = actionUrl x `mplus` actionUrl y
    , actionFunction     = \_ ->
        liftM2 M.union (runHakyllAction x) (runHakyllAction y)
    }

-- | Combine two @Context@s and set a custom URL. This behaves like @combine@,
--   except that for the @url@ field, the given URL is always chosen.
combineWithUrl :: FilePath
               -> HakyllAction () Context
               -> HakyllAction () Context
               -> HakyllAction () Context
combineWithUrl url x y = combine'
    { actionUrl          = Just $ return url
    , actionFunction     = \_ -> M.insert "url" url <$> runHakyllAction combine'
    }
  where
    combine' = combine x y
