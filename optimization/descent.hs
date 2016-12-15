import Graphics.Gloss
import Data.Function
import Graphics.Gloss.Interface.Pure.Game
import System.Random
import Debug.Trace

main = play                    -- TODO change to play
       (InWindow "optimization-based layout" -- display mode, window name
                  (picWidth, picHeight)   -- size
                  (10, 10))    -- position
       white                   -- background color
       50                     -- number of simulation steps to take for each second of real time
       initState                   -- the initial world
       picOf                   -- fn to convert world to a pic
       handler                 -- fn to handle input events
       step                    -- step the world one iteration; passed period of time (in secs) to be advanced

picWidth :: Int 
picWidth = 800

picHeight :: Int
picHeight = 700

class Located a where
      getX :: a -> Float
      getY :: a -> Float
      setX :: Float -> a -> a
      setY :: Float -> a -> a

class Selectable a where
      select :: a -> a
      deselect :: a -> a
      selected :: a -> Bool

data Circ = Circ { xc :: Float
                 , yc :: Float
                 , r :: Float
                 , selc :: Bool } 

instance Located Circ where
         getX c = xc c
         getY c = yc c
         setX x c = c { xc = x }
         setY y c = c { yc = y }         

instance Selectable Circ where
         select x = x { selc = True }
         deselect x = x { selc = False }
         selected x = selc x

data Label = Label { xl :: Float
                   , yl :: Float
                   , textl :: String
                   , scalel :: Float  -- calculate h,w from it
                   , sell :: Bool } -- selected label

instance Located Label where
         getX l = xl l
         getY l = yl l
         setX x l = l { xl = x }
         setY y l = l { yl = y }

instance Selectable Label where
         select x = x { sell = True }
         deselect x = x { sell = False }
         selected x = sell x         

data Obj = C Circ | L Label -- | Label | Point | Line // is there a better way to do this?
-- instance Located Obj

-- is there some way to reduce the top-level boilerplate?
instance Located Obj where
         getX o = case o of
                 C c -> getX c
                 L l -> getX l
         getY o = case o of
                 C c -> getY c
                 L l -> getY l
         setX x o = case o of
                C c -> C $ setX x c 
                L l -> L $ setX x l
         setY y o = case o of
                C c -> C $ setY y c
                L l -> L $ setY y l

instance Selectable Obj where
         select x = case x of
                C c -> C $ select c
                L l -> L $ select l
         deselect x = case x of
                C c -> C $ deselect c
                L l -> L $ deselect l
         selected x = case x of
                C c -> selected c
                L l -> selected l

data State = State { objs :: [Obj]
                   , down :: Bool -- left mouse button is down (dragging)
                   , rng :: StdGen } 

initRng :: StdGen
initRng = mkStdGen seed
    where seed = 11 -- deterministic RNG with seed

rad = 100 -- TODO don't hardcode into constant

clamp1D y = if clampflag then 0 else y

-- TODO randomly sample s0
initState :: State
initState = State { objs = objsInit, down = False, rng = initRng }
          where objsInit = [c1, c2] -- only handles two objects!
                c1 = C $ Circ { xc = -300, yc = clamp1D 200, r = rad, selc = False }
                c2 = C $ Circ { xc = 300, yc = clamp1D (-200), r = rad-50, selc = False }          
                l1 = L $ Label { xl = -100, yl = clamp1D 200, textl = "B1", scalel = 0.2, sell = False }

-- divide two integers to obtain a float
divf :: Int -> Int -> Float
divf a b = (fromIntegral a) / (fromIntegral b)

pw2 = picWidth `divf` 2
ph2 = picHeight `divf` 2
widthRange = (-pw2, pw2)
heightRange = (-ph2, ph2)

renderCirc :: Circ -> Picture
renderCirc c = color scolor $ translate (xc c) (yc c) $ circle (r c)
           where scolor = if selected c then green else light violet

renderLabel :: Label -> Picture
renderLabel l = color scolor $ translate (xl l) (yl l) $ scale 0.2 0.2 $ text (textl l)
            where scolor = if selected l then green else light violet

renderObj :: Obj -> Picture
renderObj (C circ) = renderCirc circ
renderObj (L label) = renderLabel label

picOfState :: State -> Picture
picOfState s = Pictures $ map renderObj (objs s)

picOf :: State -> Picture
picOf s = Pictures [picOfState s, objectiveTxt]
    where lineX = Line [(-pw2, 0), (pw2, 0)] -- unused
          lineY = Line [(0, -ph2), (0, ph2)]
          objectiveTxt = translate (-pw2+50) (ph2-50) $ scale 0.1 0.1
                         $ text "objective: stay close to the center but away from other set"

---- sampling
-- generate an infinite list of sampled elements
-- keep the last generator for the "good" element
genMany :: RandomGen g => g -> (g -> (a, g)) -> [(a, g)]
genMany gen genOne = iterate (\(c, g) -> genOne g) (genOne gen)

-- take the first element that satisfies the condition
-- not the most efficient impl. also assumes infinite list s.t. head always exists
crop :: RandomGen g => (a -> Bool) -> [(a, g)] -> (a, g)
crop cond xs = --(takeWhile (not . cond) (map fst xs), -- drop gens
                head $ dropWhile (\(x, _) -> not $ cond x) xs -- keep good's gen

-- randomly sample location
-- TODO deal with circle and label separately, and take into account bbox
sampleCoord :: Located a => RandomGen g => g -> a -> (a, g)
sampleCoord gen o = (setX x' $ setY (clamp1D y') o, gen2)
        where (x', gen1) = randomR widthRange gen
              (y', gen2) = randomR heightRange gen1

-- sample each object independently, threading thru gen
stateMap :: RandomGen g => g -> (g -> a -> (b, g)) -> [a] -> ([b], g)
stateMap gen f [] = ([], gen)
stateMap gen f (x:xs) = let (x', gen') = f gen x in
                        let (xs', gen'') = stateMap gen' f xs in
                        (x' : xs', gen'')

-- sample a state
genState :: RandomGen g => [Obj] -> g -> ([Obj], g)
genState shapes gen = stateMap gen sampleCoord shapes

-- sample entire state at once until constraint is satisfied
-- TODO doesn't take into account pairwise constraints or results from objects sampled first, sequentially
sampleConstrainedState :: RandomGen g => g -> [Obj] -> ([Obj], g)
sampleConstrainedState gen shapes = (state', gen')
       where (state', gen') = crop constraint states
             states = genMany gen (genState shapes)
             -- init state params are ignored; we just need to know what kinds of objects are in it
----

bbox = 60 -- TODO put all flags and consts together

dist :: Point -> Point -> Float
dist (x1, y1) (x2, y2) = sqrt ((x1 - x2)^2 + (y1 - y2)^2)

-- hardcode bbox of at the center
-- TODO properly get bbox; rn text is centered at bottom left
inObj :: (Float, Float) -> Obj -> Bool
inObj (xm, ym) (L o) = abs (xm - getX o) <= bbox && abs (ym - getY o) <= bbox -- is label
inObj (xm, ym) (C o) = dist (xm, ym) (xc o, yc o) <= r o -- is circle

-- TODO "in object" tests
-- TODO press key to GD step
handler :: Event -> State -> State
handler (EventKey (MouseButton LeftButton) Down _ (xm, ym)) s =
        s { objs = objsFirstSelected, down = True }
        -- so that clicking doesn't select all overlapping objects in bbox
        -- foldl will reverse the list each time, so a diff obj can be selected
        -- foldr will preserve the list order, so objects are stepped consistently
        where (objsFirstSelected, _) = foldr (flip $ selectFirstIfContains (xm, ym)) ([], False) (objs s)
              selectFirstIfContains (x, y) (xs, alreadySelected) o =
                                    if alreadySelected || (not $ inObj (x, y) o) then (o : xs, alreadySelected)
                                    else (select (setX xm $ setY ym o) : xs, True)
-- dragging mouse when down 
-- if an object is selected, then if the collection of objects with the object moved satisfies the constraint, 
-- then move the object to mouse position
-- TODO there's probably a better way to implement that
handler (EventMotion (xm, ym)) s =
        if down s then s { objs = map (ifSelectedMoveToConstrained (xm, ym)) (objs s), down = down s }
        else s 
        where ifSelectedMoveToConstrained (xm, ym) o = if selected o && constraint objsWithSelectedMoved
                                               -- the constraint would be satisfied on the new mouse position
                                                      then setX xm $ setY (clamp1D ym) o else o
              objsWithSelectedMoved = map (ifSelectedMoveTo (xm, ym)) (objs s)
              ifSelectedMoveTo (xm, ym) o = if selected o then setX xm $ setY (clamp1D ym) o else o

handler (EventKey (MouseButton LeftButton) Up _ _) s =
        s { objs = map deselect $ objs s, down = False }

-- if you press a key while down, then the handler resets the entire state (then Up will just reset again)
handler (EventKey (Char 'r') Up _ _) s =
        State { objs = objs', down = False, rng = rng' }
        where (objs', rng') = sampleConstrainedState (rng s) (objs s)
handler _ s = s

-- TODO clamp needs to take into account bbox of object
clampX :: Float -> Float
clampX x = if x < -pw2 then -pw2 else if x > pw2 then pw2 else x

clampY :: Float -> Float
clampY y = if y < -ph2 then -ph2 else if y > ph2 then ph2 else y

-- TODO hack so i don't have to deal with pairwise derivatives of an arbitrary-length list
firstTwo :: [a] -> (a, a)
firstTwo (x1 : x2 : _) = (x1, x2)

-- implement gradient descent
-- TODO: is there a haskell autodifferentiator?
-- TODO: step state
type Time = Float

step :: Time -> State -> State
step t s = -- if down s then s -- don't step when dragging 
            if stepFlag then s { objs = stepObjs t $ firstTwo (objs s), down = down s} else s

stepT :: Time -> Float -> Float -> Float
stepT dt x dfdx = x - dt * dfdx

stepFlag = True
clampflag = False
debug = True
constraintFlag = True
debugF = if debug then traceShowId else id
constraint = if constraintFlag then noOverlap else \x -> True
objFn = repel'
type ObjFn = Float -> Float -> Float -> Float -> (Float, Float, Float, Float)

-- return true iff satisfied
-- TODO deal with labels and more than two objects
noOverlap :: [Obj] -> Bool
noOverlap ((C c1) : (C c2) : _) = dist (xc c1, yc c1) (xc c2, yc c2) > r c1 + r c2
-- noOverlap _ _ = True

-- layer of stepping relative to actual objects (their sizes, properties, bbox) and top-level bbox
-- step only if the constraint on the state is satisfied
-- the state will be stuck if the constraint starts out unsatisfied. TODO let GD attempt to satisfy constraint
-- TODO: also enforce for mouse dragging and initial sampling
stepObjs :: Time -> (Obj, Obj) -> [Obj]
stepObjs t (o1, o2) = if constraint objs' then objs' else [o1, o2]
        where (x1, y1, x2, y2) = (getX o1, getY o1, getX o2, getY o2)
              (x1', x2', y1', y2') = stepWithObjective objFn t x1 x2 y1 y2
              (x1'c, x2'c, y1'c, y2'c) = (clampX x1', clampX x2', clampY y1', clampY y2')
              objs' = [setX x1'c $ setY y1'c o1, setX x2'c $ setY y2'c o2]
              
-- calculates the new state
stepWithObjective :: ObjFn -> Time -> Float -> Float -> Float -> Float -> (Float, Float, Float, Float)
stepWithObjective f t x1 x2 y1 y2 = (stepT t' x1 dfdx1, stepT t' x2 dfdx2,
                                     stepT t' y1 dfdy1, stepT t' y2 dfdy2)
                  where t' = t/10
                        (dfdx1, dfdx2, dfdy1, dfdy2) = f x1 x2 y1 y2

debugXY x1 x2 y1 y2 = if debug then trace (show x1 ++ " " ++ show x2 ++ " " ++ show y1 ++ " " ++ show y2 ++ "\n") else id

-- derivative with respect to x1 of f(x1, x2, y1, y2) =  sqrt(x1^2 + y1^2) + sqrt(x2^2+y2^2)
centerObjs :: Float -> Float -> Float -> Float -> (Float, Float, Float, Float)
centerObjs x1 x2 y1 y2 = (dfdx1, dfdx2, dfdy1, dfdy2)
              where -- TODO NaNs galore
                    dfdx1 = debugF $ x1 / sqrt(x1^2 + y1^2)
                    dfdx2 = debugXY x1 x2 y1 y2 $ x2 / sqrt(x2^2 + y2^2)
                    dfdy1 = y1 / sqrt(x1^2 + y1^2)
                    dfdy2 = y2 / sqrt(x2^2 + y2^2)

-- derivative with respect to x1 of f(x1, x2, y1, y2) = -sqrt((x1-x2)^2+(y1-y2)^2) 
repel :: Float -> Float -> Float -> Float -> (Float, Float, Float, Float)
repel x1 x2 y1 y2 = (dfdx1, dfdx2, dfdy1, dfdy2)
              where -- TODO NaNs galore
                    dfdx1 = debugF $ (x1 - x2)/sqrt((x1 - x2)^2 + (y1 - y2)^2)
                    dfdx2 = debugXY x1 x2 y1 y2 $ (x1 - x2)/sqrt((x1 - x2)^2 + (y1 - y2)^2)
                    dfdy1 = - (y1 - y2)/sqrt((x1 - x2)^2 + (y1 - y2)^2)
                    dfdy2 = (y1 - y2)/sqrt((x1 - x2)^2 + (y1 - y2)^2)

repel' :: Float -> Float -> Float -> Float -> (Float, Float, Float, Float)
repel' x1 x2 y1 y2 = (dfdx1 + fac * dfdx1', dfdx2 + fac * dfdx2', dfdy1 + fac * dfdy1', dfdy2 + fac * dfdy2')
              where -- TODO NaNs galore
                    dfdx1 = debugF $ -x1 + x2
                    dfdx2 = debugXY x1 x2 y1 y2 $ -x2 + x1
                    dfdy1 = -y1 + y2
                    dfdy2 = -y2 + y1
                    (dfdx1', dfdx2', dfdy1', dfdy2') = centerObjs x1 x2 y1 y2
                    fac = 10000

-- derivative with respect to x1 of f(x1, x2, y1, y2) = -sqrt((x1-x2)^2+(y1-y2)^2) + sqrt(x1^2 + y1^2) + sqrt(x2^2+y2^2)
centerAndRepel' :: Float -> Float -> Float -> Float -> (Float, Float, Float, Float)
centerAndRepel' x1 x2 y1 y2 = (dfdx1, dfdx2, dfdy1, dfdy2)
              where -- TODO NaNs galore
                    dfdx1 = debugF $
                            sqrt(x1^2 + y1^2) - (x1 - x2)/sqrt((x1 - x2)^2 + (y1 - y2)^2)
                    dfdx2 = debugXY x1 x2 y1 y2 $
                            (x1 - x2)/sqrt((x1 - x2)^2 + (y1 - y2)^2) + x2/sqrt(x2^2 + y2^2)
                    dfdy1 = y1/sqrt(x1^2 + y1^2) - (y1 - y2)/sqrt((x1 - x2)^2 + (y1 - y2)^2)
                    dfdy2 = (y1 - y2)/sqrt((x1 - x2)^2 + (y1 - y2)^2) + y2/sqrt(x2^2 + y2^2)
                  
-- TODO can't figure out how to get the repelling behavior as optimization; may have to be a constraint
centerAndRepel :: Float -> Float -> Float -> Float -> (Float, Float, Float, Float)
centerAndRepel x1 x2 y1 y2 = (dfdx1, dfdx2, dfdy1, dfdy2)
              where -- first two terms repel from other circle; last term attracts to center
                    dfdx1 = debugF $ -2*x1^3 + 2*x2^3 + 4*x1^3
                    dfdx2 = 2*x1^3 - 2*x2^3 + 4*x2^3
                   -- TODO not correct wrt minimizing 2d distance, but it works well enough
                    dfdy1 = -2*y1^3 + 2*y2^3 + 4*y1^3 
                    dfdy2 = 2*y1^3 - 2*y2^3 + 4*y2^3

------- parameters specific to cubicCenterOrRadius

eps :: Float
eps = 60 -- why is this 100??

c1 :: Float
c1 = rad -- both need to be non-neg

c2 :: Float
c2 = rad + eps

tFactor :: Float
tFactor = 5 * 10^3

maxGrad :: Float
maxGrad = 10^7

minGrad :: Float
minGrad = 10^6

zeroClamp :: Float
zeroClamp = 5 * 10^3

-- clamp abs val of grad within [minGrad, maxGrad]
-- TODO clamp so small gradient = 0 movement, so no jitter
gradClamp :: Float -> Float
gradClamp g = if abs g < zeroClamp then 0 -- clamp down
              else if abs g < minGrad then sign * minGrad -- clamp up
              else if abs g > maxGrad then sign * maxGrad -- clamp down
              else g
              where sign = if g < 0 then -1 else 1

-- objective functions, differentiated and discretized
-- attract label to center of circle or to outside of circle
-- wolframalpha: derivative with respect to x1 of f(x1, y1, x2, y2) = (sqrt((x1-x2)^2 + (y1-y2)^2))^3 - (c1 + c2) (sqrt((x1-x2)^2 + (y1-y2)^2))^2 + c1 * c2 * (sqrt((x1-x2)^2 + (y1-y2)^2))
-- to debug, use traceShowId :: Show a => a -> a
cubicCenterOrRadius :: Time -> Float -> Float -> Float -> Float -> (Float, Float, Float, Float)
cubicCenterOrRadius t x1 x2 y1 y2 = ({-traceShowId $ -}stepT t' x1 dx1, stepT t' x2 dx2,
                                     stepT t' y1 dy1, stepT t' y2 dy2)
              where t' = t/tFactor -- otherwise it jitters b/t -inf and inf, doesn't reach zeroes
                    -- doesn't settle in the outside correctly
                    -- instantly jumps to inside bc grad is probably very large, but slow inside
                    -- and if too far away, jitters between -bigval and bigval until clicked/dragged
                    -- also, these are in fact dx1/dt (etc.)
                    -- need to hand-calibrate timestepping and clamping
                    -- TODO if x1 = x2 and y1 = y2, then NaN
                    -- TODO step each one WRT the already-stepped ones to reduce jitter?
                    dx1 = gradClamp $ {-traceShowId $-} (-2)*(c1 + c2)*(x1 - x2) + (c1*c2*(x1 - x2))/sqrt((x1 - x2)^2 + (y1 - y2)^2) + 3*(x1 - x2)*sqrt((x1 - x2)^2 + (y1 - y2)^2)
                    dy1 = gradClamp $ (-2)*(c1 + c2)*(y1 - y2) + (c1*c2*(y1 - y2))/sqrt((x1 - x2)^2 + (y1 - y2)^2) + 3*sqrt((x1 - x2)^2 + (y1 - y2)^2)*(y1 - y2)
                    -- same as dx1 and dy1 except moving toward each other
                    dx2 = -1 * (gradClamp $ traceShowId $ (-2)*(c1 + c2)*(x1 - x2) + (c1*c2*(x1 - x2))/sqrt((x1 - x2)^2 + (y1 - y2)^2) + 3*(x1 - x2)*sqrt((x1 - x2)^2 + (y1 - y2)^2))
                    dy2 = -1 * (gradClamp $ (-2)*(c1 + c2)*(y1 - y2) + (c1*c2*(y1 - y2))/sqrt((x1 - x2)^2 + (y1 - y2)^2) + 3*sqrt((x1 - x2)^2 + (y1 - y2)^2)*(y1 - y2))

-- attract: f(x1, x2) = (x1-x2)^2
-- df/dx1 = 2(x1-x2), df/dx2 = -2(x1-x2)
distance1d :: Time -> Float -> Float -> (Float, Float)
distance1d t x1 x2 = (x1 - t * 2 * (x1 - x2), x2 + t * 2 * (x1 - x2))
-- x2 does not use the updated x1

-- repel
negdistance1d :: Time -> Float -> Float -> (Float, Float)
negdistance1d t x1 x2 = (x1 + t * 2 * (x1 - x2), x2 - t * 2 * (x1 - x2))   

-- f(x) = x^2
parabola' :: Time -> Float -> Float
parabola' t x = x - t * 2 * x

neg_parabola' :: Time -> Float -> Float
neg_parabola' t x = x + t * 2 * x
