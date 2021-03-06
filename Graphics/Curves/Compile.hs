
module Graphics.Curves.Compile where

import Prelude hiding (minimum, maximum, any, or, and)
import Control.Applicative
import Data.Foldable
import Data.Monoid

import Graphics.Curves.Math
import Graphics.Curves.BoundingBox
import Graphics.Curves.Image
import Graphics.Curves.Colour
import Graphics.Curves.Curve

import Debug.Trace

-- Compilation ------------------------------------------------------------

type Segments = BBTree (AnnotatedSegment LineStyle)

data FillStyle = FillStyle FillColour Scalar Basis LineStyle
data LineStyle = LineStyle Colour Scalar Scalar

instance Monoid LineStyle where
  mempty  = LineStyle transparent 0 0
  mappend (LineStyle c1 w1 b1) (LineStyle c2 w2 b2) =
    LineStyle (c1 `blend` c2) (max w1 w2) (max b1 b2)

data CompiledImage
      = Segments FillStyle Segments
      | CIUnion (Op (Maybe Colour)) BoundingBox CompiledImage CompiledImage
      | CIEmpty

instance HasBoundingBox CompiledImage where
  bounds (Segments fs b) = relaxBoundingBox (max fw lw) $ bounds b
    where
      fw = case fs of
             FillStyle (SolidFill c) _ _ _ | isTransparent c -> 0
             FillStyle _ w _ _ -> w / 2
      lw = case fs of
             FillStyle _ _ _ (LineStyle c w b) | not $ isTransparent c -> w + b
             _ -> 0
  bounds (CIUnion _ b _ _) = b
  bounds CIEmpty           = Empty

compileImage :: Image -> CompiledImage
compileImage = compileImage' 1

compileImage' :: Scalar -> Image -> CompiledImage
compileImage' res (ICurve c) = Segments fs ss
  where
    s  = curveFillStyle c
    fs = FillStyle (fillColour s) (fillBlur s) (textureBasis s) (foldMap annotation ss)
    ss = fmap (\(_, _, s) -> toLineStyle s) <$> curveToSegments res c
    toLineStyle s = LineStyle (lineColour s) (lineWidth s) (lineBlur s)
compileImage' res IEmpty = CIEmpty
compileImage' res (Combine blend a b) =
  CIUnion blend (bounds (ca, cb)) ca cb
  where
    ca = compileImage' res a
    cb = compileImage' res b

