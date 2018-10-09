{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving  #-}
--------------------------------------------------------------------------------
module Sarah.GUI.Remote.Power.HS110
  where
--------------------------------------------------------------------------------
import Control.Monad                       (forM, void)
import Control.Monad.Reader                (lift, ask)
import Control.Monad.IO.Class              (liftIO)
import Data.Foldable                       (traverse_)
import Data.Text                           (unwords, pack)
import Graphics.UI.Material
import Graphics.UI.Threepenny              (UI, Handler, register, currentValue, runFunction, ffi)
import Prelude                      hiding (unwords)
import Sarah.GUI.Model
import Sarah.GUI.Reactive
import Sarah.GUI.Websocket
import Sarah.Middleware
import Sarah.Middleware.Device.Power.HS110
--------------------------------------------------------------------------------
import qualified Text.Blaze.Html5            as H
import qualified Text.Blaze.Html5.Attributes as A
--------------------------------------------------------------------------------

deriving instance Show (DeviceRequest HS110)

instance HasSelection (DeviceRequest HS110) where
  toSelectionLabel PowerOn            = "Power On"
  toSelectionLabel PowerOff           = "Power Off"
  toSelectionLabel GetStateRequest    = "Get State"
  toSelectionLabel GetReadingsRequest = "Get Readings"

  fromSelectionLabel "Power On"     = Right PowerOn
  fromSelectionLabel "Power Off"    = Right PowerOff
  fromSelectionLabel "Get State"    = Right GetStateRequest
  fromSelectionLabel "Get Readings" = Right GetReadingsRequest
  fromSelectionLabel t              = unexpectedSelectionLabel t

instance HasRemote HS110 where
  buildRemote _ = do
    RemoteBuilderEnv{..} <- ask

    powerSwitch <- lift $ reactiveToggle False

    let eventStateChangedHandler :: Handler (DeviceState HS110)
        eventStateChangedHandler HS110State{..} = getHandler powerSwitch isOn

    unregister <- liftIO $ register (decodeDeviceState <$> eventStateChanged) (traverse_ eventStateChangedHandler)

    addPageAction $
      onElementIDCheckedChange (getItemId powerSwitch) $ \state -> runRemote $
        withoutResponse $
          if state
            then PowerOn
            else PowerOff

    addPageTile $
      let title = unwords [deviceNode deviceAddress, deviceName deviceAddress]
          img   = Nothing -- Just "static/img/remote/power.png"
      in mkTileSmall title img $ list [ listItem (H.text "Power") $ getItem powerSwitch ]

    -- get the state of the device
    addPageAction $
      runRemote $
        withResponse GetStateRequest
        doNothing
        (\(GetStateReply state) -> eventStateChangedHandler state)


  buildSchedule _ = do
    ScheduleBuilderEnv{..} <- ask
    schedule               <- getSchedule

    optionPowerOn  <- lift $ reactiveOption PowerOn
    optionPowerOff <- lift $ reactiveOption PowerOff
    scheduleAction <- lift $ reactiveSelectField [optionPowerOn, optionPowerOff] PowerOn
    scheduleTimer  <- lift timerInput

    addItemButton   <- button Nothing (Just "Add")
    addItemDialogue <- dialogue "Add schedule" $ list [ getItem scheduleAction
                                                      , getItem scheduleTimer
                                                      ]

    traverse_ addPageAction (getPageActions scheduleTimer)

    -- addPageAction $
    --   onElementIDChange (getItemId scheduleTimer) $ \(newSelection :: TimerInputOptions) -> do
    --     runFunction $ ffi "console.log('New selection: %1')" (show newSelection)
    --     liftIO . putStrLn $ "New option is " ++ show newSelection

    -- display the dialogue to add a schedule item
    addPageAction $
      onElementIDClick (getItemId addItemButton) $
        showDialogue (getItemId addItemDialogue)

    -- submitting the new schedule item through the dialogue
    addPageAction $
      onElementIDClick (getSubmitButtonId addItemDialogue) $ do
        hideDialogue (getItemId addItemDialogue)

        mAction <- getInput scheduleAction :: UI (Maybe (DeviceRequest HS110))
        mTimer  <- getInput scheduleTimer  :: UI (Maybe Timer)

        case (,) <$> mAction <*> mTimer of
          Nothing              -> toast "Could not create schedule: invalid input."
          Just (action, timer) -> do
            let request = CreateScheduleRequest (Schedule deviceAddress (mkQuery deviceAddress action) timer)
            void $ toMaster middleware request

    -- hide the dialogue
    -- ToDo: should we reset the input elements?
    addPageAction $
      onElementIDClick (getDismissButtonId addItemDialogue) $
        hideDialogue (getItemId addItemDialogue)

    -- we have to add the dialogue to the page under body (otherwise the dialogue
    -- may not work properly)
    addPageDialogue $
      getItem addItemDialogue

    -- and the tile for the device
    addPageTile $
      let title         = unwords [deviceNode deviceAddress, deviceName deviceAddress]
          img           = Nothing
          scheduleItems = map (\(_, Schedule{..}) -> case getCommand . queryCommand $ scheduleAction of
                                                       Left err                               -> mempty
                                                       Right (command :: DeviceRequest HS110) -> listItem (H.text . pack . show $ scheduleTimer)
                                                                                                          (H.text . pack . show $ command)
                              ) schedule
      in mkTileSmall title img (list $ scheduleItems ++ [getItem addItemButton])
