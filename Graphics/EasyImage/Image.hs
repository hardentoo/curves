
module Graphics.EasyImage.Image
  ( module Graphics.EasyImage.Image
  , (<>) )
  where

import Data.Monoid
import Data.List
import Data.Maybe

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

mapCurves :: (Curve -> Curve) -> Image -> Image
mapCurves f (ICurve c) = ICurve (f c)
mapCurves f (Union b is) = Union b (map (mapCurves f) is)

reverseImage :: Image -> Image
reverseImage = mapCurves reverseCurve

-- | Freeze the size of an image.
freezeImageSize :: Point -> Image -> Image
freezeImageSize p = mapCurves (freezeCurve fr p)
  where
    fr = Freeze{ freezeSize = True, freezeOrientation = False }

-- | Freeze both image orientation
freezeImageOrientation :: Point -> Image -> Image
freezeImageOrientation p = mapCurves (freezeCurve fr p)
  where
    fr = Freeze{ freezeSize = False, freezeOrientation = True }

-- | Freeze both size and orientation
freezeImage :: Point -> Image -> Image
freezeImage p = mapCurves (freezeCurve fr p)
  where
    fr = Freeze{ freezeSize = True, freezeOrientation = True }

with :: Image -> [Attr] -> Image
with i as = onStyle i $ foldr (.) id $ map setAttr as
  where
    onStyle :: Image -> (CurveStyle -> CurveStyle) -> Image
    onStyle i f = mapCurves (\c -> c { curveStyle = f $ curveStyle c }) i

instance Transformable Image where
  transform f = mapCurves (transform f)

infixl 8 +++, <++
infixr 7 ++>
(+++) :: Image -> Image -> Image
ICurve c1 +++ ICurve c2 = ICurve $ joinCurve c1 c2
ICurve c +++ Union _ [] = ICurve c
ICurve c +++ Union b (i:is) = Union b ((ICurve c +++ i) : is)
Union b is +++ ICurve c = Union b (init is ++ [last is +++ ICurve c])
_ +++ _ = error "(+++) on non-curves"

(<++) :: Point -> Image -> Image
p <++ ICurve c       = ICurve $ prependPoint p c
p <++ Union b (i:is) = Union b $ (p <++ i) : is
_ <++ Union _ []     = error "_ <++ mempty"

(++>) :: Image -> Point -> Image
ICurve c   ++> p = ICurve $ appendPoint c p
Union _ [] ++> _ = error "mempty ++> _"
Union b is ++> p = Union b $ init is ++ [last is ++> p]

-- B-Splines --------------------------------------------------------------

bSpline :: [Point] -> Image
bSpline ps = foldl1 (+++) $ map seg (takeWhile ((>=4).length) $ map (take 4) (tails ps))
  where
    m = map (map (/ 6)) [[-1, 3, -3, 1], [3, -6, 0, 4], [-3, 3, 3, 1], [1, 0, 0, 0]]
    coefs t = map diag $ mmul [t^3, t^2, t, 1] m
    mmul v m = map (vmul v) m
    vmul u v = sum $ zipWith (*) u v

    seg ps = curve f 0 1
      where
        f t = vmul (coefs t) ps

closedBSpline :: [Point] -> Image
closedBSpline ps = bSpline $ ps ++ take 3 ps

bSpline' (p:ps) = bSpline $ p:p:p:ps ++ replicate 2 (last (p:ps))

-- ImageElement -----------------------------------------------------------

class Transformable a => ImageElement a where
  render :: a -> Image

instance ImageElement Image where
  render = id

instance ImageElement Segment where
  render (Seg p q) = line p q

instance ImageElement Vec where
  render = point
