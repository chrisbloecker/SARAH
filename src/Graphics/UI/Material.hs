module Graphics.UI.Material
  ( module Graphics.UI.Material
  )
  where
--------------------------------------------------------------------------------
import Control.Monad                     (forM)
import Data.UUID                         (toString)
import Data.UUID.V4                      (nextRandom)
import Graphics.UI.Threepenny     hiding (map)
import Prelude                    hiding (div, span)
--------------------------------------------------------------------------------
import Graphics.UI.Material.Class    as Graphics.UI.Material
import Graphics.UI.Material.Icon     as Graphics.UI.Material
import Graphics.UI.Material.Reactive as Graphics.UI.Material
--------------------------------------------------------------------------------

upgradeDom :: UI ()
upgradeDom = runFunction $ ffi "componentHandler.upgradeDom();console.log('component upgrade ok.')"


data List = List { _elementList :: Element }

instance Widget List where
  getElement = _elementList

list :: [UI ListItem] -> UI List
list items = do
  elem <- div #+ [ ul # set class_ (unClass mdl_list)
                     #+ map (fmap getElement) items
                 ]

  return List { _elementList = elem }


data ListItem = ListItem { _elementListItem :: Element }

instance Widget ListItem where
  getElement = _elementListItem

listItem :: (Widget widget0, Widget widget1) => UI widget0 -> UI widget1 -> UI ListItem
listItem content action = do
  elem <- li # set class_ (unClass mdl_list_item)
             #+ [ span # set class_ (unClass mdl_list_item_primary_content)  #+ [ getElement <$> content ]
                , span # set class_ (unClass mdl_list_item_secondary_action) #+ [ getElement <$> action  ]
                ]

  return ListItem { _elementListItem = elem }


data Slider = Slider { getSlider :: Element }

instance Widget Slider where
  getElement = getSlider

slider :: Int -> Int -> Int -> Int -> UI Slider
slider width min max value = do
  elem <- p # set style [("width", show width ++ "px")]
            #+ [ input # set class_ (unClass $ buildClass [mdl_slider, mdl_js_slider])
                       # set type_ "range"
                       # set (attr "min") (show min)
                       # set (attr "max") (show max)
                       # set (attr "value") (show value)
                       # set (attr "step") "1"
               ]

  return Slider { getSlider = elem }