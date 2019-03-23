{-# LANGUAGE ConstraintKinds        #-}
{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE DefaultSignatures      #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE PolyKinds              #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE TypeOperators          #-}
{-# LANGUAGE UndecidableInstances   #-}
module Data.Vec.DataFamily.SpineStrict.Pigeonhole (
    Pigeonhole (..),
    -- * Representable
    gindex,
    gtabulate,
    -- * Generic implementation
    gfrom, GFrom,
    gto, GTo,
    GPigeonholeSize,
    ) where

import Control.Arrow                   (first)
import Data.Functor.Identity           (Identity (..))
import Data.Functor.Product            (Product (..))
import Data.Functor.Rep                (tabulate)
import Data.Nat                        (Nat)
import Data.Proxy                      (Proxy (..))
import Data.Vec.DataFamily.SpineStrict (Vec (..))
import GHC.Generics                    ((:*:) (..), M1 (..), Par1 (..), U1 (..))

import qualified Data.Fin.Enum                   as F
import qualified Data.Type.Nat                   as N
import qualified Data.Vec.DataFamily.SpineStrict as V
import qualified GHC.Generics                    as G

-- $setup
-- >>> :set -XDeriveGeneric
-- >>> import Data.Void (absurd)
-- >>> import GHC.Generics (Generic, Generic1)

-------------------------------------------------------------------------------
-- Class
-------------------------------------------------------------------------------

-- | Generic pigeonholes.
--
-- /Examples:/
--
-- >>> from (Identity 'a')
-- 'a' ::: VNil
--
-- >>> data Values a = Values a a a deriving (Generic1)
-- >>> instance Pigeonhole Values
-- >>> from (Values 1 2 3)
-- 1 ::: 2 ::: 3 ::: VNil
--
class Pigeonhole f where
    -- | The size of a pigeonhole
    type PigeonholeSize f :: Nat
    type PigeonholeSize f = GPigeonholeSize f

    -- | Converts a value to vector
    from :: f x -> Vec (PigeonholeSize f) x
    default from :: (G.Generic1 f, GFrom f, PigeonholeSize f ~ GPigeonholeSize f) => f x -> Vec (PigeonholeSize f) x
    from = gfrom

    -- | Converts back from vector.
    to :: Vec (PigeonholeSize f) x -> f x
    default to :: (G.Generic1 f, GTo f, PigeonholeSize f ~ GPigeonholeSize f) => Vec (PigeonholeSize f) x -> f x
    to = gto

-- | @'Identity' x@ ~ @x ^ 1@
instance Pigeonhole Identity
--
-- | @'Proxy' x@ ~ @x ^ 0@
instance Pigeonhole Proxy

-- | @'Product' f g x@ ~ @x ^ (size f + size g)@
instance (Pigeonhole f, Pigeonhole g, N.InlineInduction (PigeonholeSize f)) => Pigeonhole (Product f g) where
    type PigeonholeSize (Product f g) = N.Plus (PigeonholeSize f) (PigeonholeSize g)

    to = f . V.split where f (a, b) = Pair (to a) (to b)
    from = uncurry (V.++) . g where g (Pair a b) = (from a, from b)

-------------------------------------------------------------------------------
-- Generic representable
-------------------------------------------------------------------------------

-- | Index.
--
-- >>> gindex (Identity 'y') (Proxy :: Proxy Int)
-- 'y'
--
-- >>> data Key = Key1 | Key2 | Key3 deriving (Generic)
-- >>> data Values a = Values a a a deriving (Generic1)
--
-- >>> gindex (Values 'a' 'b' 'c') Key2
-- 'b'
--
gindex
    :: ( G.Generic i, F.GFrom i, G.Generic1 f, GFrom f
       , F.GEnumSize i ~ GPigeonholeSize f, N.InlineInduction (GPigeonholeSize f)
       )
     => f a -> i -> a
gindex fa i = gfrom fa V.! F.gfrom i

-- | Tabulate.
--
-- >>> tabulate (\() -> 'x') :: Identity Char
-- Identity 'x'
--
-- >>> tabulate absurd :: Proxy Integer
-- Proxy
--
-- >>> tabulate absurd :: Proxy Integer
-- Proxy
--
gtabulate
    :: ( G.Generic i, F.GTo i, G.Generic1 f, GTo f
       , F.GEnumSize i ~ GPigeonholeSize f, N.InlineInduction (GPigeonholeSize f)
       )
     => (i -> a) -> f a
gtabulate idx = gto $ tabulate (idx . F.gto)

-------------------------------------------------------------------------------
-- PigeonholeSize
-------------------------------------------------------------------------------

-- | Compute the size from the type.
type GPigeonholeSize c = PigeonholeSizeRep (G.Rep1 c) N.Nat0

type family PigeonholeSizeRep (c :: * -> *) (n :: Nat) :: Nat where
    PigeonholeSizeRep (a :*: b )   n = PigeonholeSizeRep a (PigeonholeSizeRep b n)
    PigeonholeSizeRep (M1 _d _c a) n = PigeonholeSizeRep a n
    PigeonholeSizeRep Par1         n = 'N.S n
    PigeonholeSizeRep U1           n = n

-------------------------------------------------------------------------------
-- From
-------------------------------------------------------------------------------

-- | Generic version of 'from'.
gfrom :: (G.Generic1 c, GFrom c) => c a -> Vec (GPigeonholeSize c) a
gfrom = \x -> gfromRep1 (G.from1 x) VNil

-- | Constraint for the class that computes 'gfrom'.
type GFrom c = GFromRep1 (G.Rep1 c)

class GFromRep1 (c :: * -> *)  where
    gfromRep1 :: c x -> Vec n x -> Vec (PigeonholeSizeRep c n) x

instance (GFromRep1 a, GFromRep1 b) => GFromRep1 (a :*: b) where
    gfromRep1 (x :*: y) z = gfromRep1 x (gfromRep1 y z)

instance GFromRep1 a => GFromRep1 (M1 d c a) where
    gfromRep1 (M1 a) z = gfromRep1 a z

instance GFromRep1 Par1 where
    gfromRep1 (Par1 x) z = x ::: z

instance GFromRep1 U1 where
    gfromRep1 _U1 z = z

-------------------------------------------------------------------------------
-- To
-------------------------------------------------------------------------------

-- | Generic version of 'to'.
gto :: forall c a. (G.Generic1 c, GTo c) => Vec (GPigeonholeSize c) a -> c a
gto = \xs -> G.to1 $ fst (gtoRep1 xs :: (G.Rep1 c a, Vec 'N.Z a))

-- | Constraint for the class that computes 'gto'.
type GTo c = GToRep1 (G.Rep1 c)

class GToRep1 (c :: * -> *) where
    gtoRep1 :: Vec (PigeonholeSizeRep c n) x -> (c x, Vec n x)

instance GToRep1 a => GToRep1 (M1 d c a) where
    gtoRep1 = first M1 . gtoRep1

instance (GToRep1 a, GToRep1 b) => GToRep1 (a :*: b) where
    gtoRep1 xs =
        let (a, ys) = gtoRep1 xs
            (b, zs) = gtoRep1 ys
        in (a :*: b, zs)

instance GToRep1 Par1 where
    gtoRep1 (x ::: xs) = (Par1 x, xs)

instance GToRep1 U1 where
    gtoRep1 xs = (U1, xs)
