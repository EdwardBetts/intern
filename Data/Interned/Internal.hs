{-# LANGUAGE TypeFamilies
           , FlexibleInstances
           , FlexibleContexts
           , GeneralizedNewtypeDeriving #-}

module Data.Interned.Internal
  ( Interned(..)
  , Uninternable(..)
  , mkCache
  , Cache(..)
  , CacheState(..)
  , Id(..)
  , intern
  ) where

import Data.Hashable
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HashMap
import Control.Concurrent.MVar
import GHC.IO (unsafeDupablePerformIO, unsafePerformIO)
import System.Mem.Weak

data CacheState t = CacheState 
   {-# UNPACK #-} !(Id t) 
   !(HashMap (Description t) (Weak t))

newtype Cache t = Cache { getCache :: MVar (CacheState t) }

instance Show (Cache t) where
  showsPrec d (Cache t) = let CacheState i m = unsafeDupablePerformIO (readMVar t) in
    showParen (d > 10) $ showString "Cache {- next: " 
                       . showsPrec 10 i 
                       . showString ", entries: "
                       . showsPrec 10 (HashMap.size m)
                       . showString " -}"

mkCache :: Cache t
mkCache = Cache $ unsafePerformIO $ newMVar $ CacheState 0 HashMap.empty

newtype Id t = Id Int deriving (Eq,Ord,Show,Num,Real,Integral,Enum)

instance Hashable (Id t) where
  hash (Id t) = hash t
  hashWithSalt s (Id t) = hashWithSalt s t

class ( Eq (Description t)
      , Hashable (Description t)
      ) => Interned t where
  data Description t
  type Uninterned t
  describe :: Uninterned t -> Description t 
  identify :: Id t -> Uninterned t -> t
  identity :: t -> Id t
  cache    :: Cache t

class Interned t => Uninternable t where
  unintern :: t -> Uninterned t

intern :: Interned t => Uninterned t -> t
intern bt = unsafeDupablePerformIO $ modifyMVar (getCache cache) go 
  where
  dt = describe bt
  go (CacheState i m) = case HashMap.lookup dt m of
    Nothing -> k i m
    Just wt -> do
      mt <- deRefWeak wt
      case mt of 
        Just t -> return (CacheState i m, t)
        Nothing -> k i m
  k i m = do let t = identify i bt 
             wt <- t `seq` mkWeakPtr t $ Just remove
             return (CacheState (i + 1) (HashMap.insert dt wt m), t)
  remove = modifyMVar_ (getCache cache) $ 
    \ (CacheState i m) -> return $ CacheState i (HashMap.delete dt m)
