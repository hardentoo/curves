
module Graphics.EasyImage.Image
  ( module Graphics.EasyImage.Image
  , (<>) )
  where

import Data.Monoid

import Graphics.EasyImage.Math
import Graphics.EasyImage.Colour
import Graphics.EasyImage.Curve
import Graphics.EasyImage.BoundingBox

-- Two representations:
--  - curve representation
--  - segments representation
--
-- Work with curve representation until just before rasterization. Then compile
-- to segment representation.

-- TODO: - explicit transformation matrices (for effiecency?)
--       - intersections
data Image = ICurve Curve
           | Union BlendFunc [Image]

-- Image operations -------------------------------------------------------

instance Monoid Image where
  mempty  = Union defaultBlendFunc []
  mappend a b = Union defaultBlendFunc [a, b]

curve :: (Scalar -> Point) -> Scalar -> Scalar -> Image
curve f = curve' f (const id)

curve' :: Transformable a => (Scalar -> a) -> (Scalar -> a -> Point) -> Scalar -> Scalar -> Image
curve' f g t0 t1 = ICurve $ Curve f g t0 t1 defaultCurveStyle

line :: Point -> Point -> Image
line p0 p1 = ICurve $ straightLine p0 p1

lineStrip :: [Point] -> Image
lineStrip (p:ps) = foldr1 (+++) $ zipWith line (p:ps) ps

poly :: [Point] -> Image
poly (p:ps) = lineStrip ([p] ++ ps ++ [p])

point :: Point -> Image
point p = curve (const p) 0 1 `with` [LineWidth 0.8]

circle :: Point -> Scalar -> Image
circle p r = circleSegment p r 0 (2 * pi)

circleSegment :: Point -> Scalar -> Scalar -> Scalar -> Image
circleSegment (Vec x y) r a b =
  curve (\α -> Vec (x + r * cos α) (y + r * sin α)) a b

with :: Image -> [Attr] -> Image
with i as = onStyle i $ foldr (.) id $ map setAttr as
  where
    onStyle :: Image -> (CurveStyle -> CurveStyle) -> Image
    onStyle (ICurve curve) f   = ICurve $ curve { curveStyle = f $ curveStyle curve }
    onStyle (Union blend is) f = Union blend $ map (`onStyle` f) is

instance Transformable Image where
  transform f (ICurve c)   = ICurve (transform f c)
  transform f (Union b is) = Union b $ map (transform f) is

infixr 8 +++
(+++) :: Image -> Image -> Image
ICurve c1 +++ ICurve c2 = ICurve $ joinCurve c1 c2
_ +++ _ = error "(+++) on non-curves"
