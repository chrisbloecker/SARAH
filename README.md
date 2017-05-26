# Smart Augmented Reality Automated Home

SARAH is a system for home automation, designed to work as a bridge between all
different sorts of devices. The current situation in smart homes is that you
have to buy the smart devices, a hub to control those devices, and you have to use
an app specific to the products you bought. It's usually a big pain, if not impossible,
to integrate devices from different manufacturers into one infrastructure. Even
worse, devices that are "pre smart home" can't be connected at all. SARAH is supposed
to help with that by providing an extensible interface for devices that can communicate
with the outside world in *some* way. Whether it be through an IR-LED that is
connected to a GPIO port somewhere, through bluetooth, or IP, all devices can be
connected.

At the moment, this project is still very much a work in progress.

## Components
SARAH consists of different components, all written in Haskell:
 * a frontend for user interaction and feedback,
 * a middleware for communication between frontend <-> devices and devices <-> devices,
 * and a database backend for persistence.

Some low level code, e.g., for sending signals through an IR-LED is written in C
and used in Haskell through [inline-c](https://hackage.haskell.org/package/inline-c).

### Frontend
The frontend is written using [threepenny-gui](https://hackage.haskell.org/package/threepenny-gui),
[material design lite](https://getmdl.io/) is used for styling. The frontend exposes
a web interface that can be used through a web browser. Commands for devices are
generated by the frontend and sent to the devices through the middleware.

### Middleware
The middleware consists of a master node and slave nodes and is basically a distributed
system. Communication between master and slave nodes is done through message passing
using [Cloud Haskell](http://haskell-distributed.github.io/). Communication between
the frontend and master node is done through websockets.

For every device that is connected to SARAH, there is a corresponding control process
running on one of the slave node (each device is connected through at most one slave
node). Commands from the frontend are routed from the frontend to the target device
first through the master node and then through the slave controller on the respective
slave node. The device controller processes the command and generates a response
that is sent back the same way, i.e. through the slave controller and then the
master node. Whenever a device state changes, the device controller sends an update
through the slave controller to the master node. The master node then informs all
registered listeners.

ToDo: change state broadcasting to active polling (this should be okay because we
will only have very few listeners)

### Database Backend
The database backend uses [servant](http://haskell-servant.readthedocs.io/) to
provide a REST interface for storing and retrieving data. [Persistent](http://www.yesodweb.com/book/persistent) is used for interaction with
a database backend (in this case currently a MySQL database).

## Hardware
I use multiple Raspberry Pi 3 and some prototyping hardware such as sensors and
IR-LEDs to interact with, e.g., TV and AC.

## Non-Haskell Dependencies
 * [libpigpio](https://github.com/joan2937/pigpio): We need a patched version of
   pigpio that simply disregards SIGVTALRM, as this signal is generated by Haskell's
   RTS. pigpio's default behaviour on SIGVTALRM would be to give up and exit.
 * [ir-slinger](https://github.com/bschwind/ir-slinger): For sending controls
   through IR-LEDs

## Supported Devices
The list of supported devices is not very long yet, but I will add more as I go
along. So far, the following devices can be connected
 * DHT11/DHT22 temperature and humidity sensor through GPIO
 * TP-Link HS110 smart power plug through IP
 * Some Toshiba ACs through GPIO (ToDo: add model identifiers)

## Adding Devices
In order to add a new device, we need a few things
 1. A data type to represent the device
 ```haskell
 newtype ExampleDevice = ExampleDevice Pin deriving (Show)
 ```
 This device will be connected through a GPIO `Pin`.

 2. An instance of `IsDevice` for the data type
 ```haskell
 instance IsDevice ExampleDevice where
   -- Define the device state
   data DeviceState ExampleDevice = On | Off
     deriving (Generic, Binary, ToJSON, FromJSON)

   -- List all the possible requests and replies the device should support
   -- DeviceRequest and DeviceReply need to have instances for ToJSON and FromJSON
   data DeviceRequest ExampleDevice = ToggleRequest
                                    | GetStateRequest
     deriving (Generic, ToJSON, FromJSON)

   data DeviceReply ExampleDevice = ToggleReply
                                  | GetStateReply (DeviceState ExampleDevice)
     deriving (Generic, ToJSON, FromJSON)

   -- setup the device and start a server that listens for commands
   startDeviceController (ExampleDevice pin) slave portManager = do
     -- start the server and wrap its pid into a DeviceController
     DeviceController <$> spawnLocal (controller Off slave portManager pin)

       where
         -- the controller listens for requests and replies to them
         controller :: DeviceState ExampleDevice -> Slave -> PortManager -> Pin -> Process ()
         controller state slave portManager pin =
           receiveWait [ match $ \(FromPid src (query :: Query)) -> case getCommand (queryCommand query) of
                           Left err -> do
                             say $ "[ExampleDevice.controller] Can't decode command: " ++ err
                             controller state slave portManager pin

                           Right command -> case command of
                             ToggleRequest -> do
                               send src (mkQueryResult $ ToggleReply)
                               let state' = case state of
                                 On  -> Off
                                 Off -> On
                               controller state' slave portManager pin

                             GetStateRequest -> do
                               send src (mkQueryResult $ GetStateReply state)
                               controller state slave portManager pin

                       , matchAny $ \m -> do
                           say $ "[ExampleDevice.controller] Received unexpected message: " ++ show m
                           controller state slave portManager pin
                       ]
 ```

 3. `FromJSON` and `ToJSON` instances for the data type
 ```haskell
 instance ToJSON ExampleDevice where
   toJSON (ExampleDevice (Pin pin)) = object [ "model" .= String "ExampleDevice"
                                             , "gpio" .= toJSON pin
                                             ]

 -- A FromJSON instance for the device is necessary so we can configure it through a yml file
 instance FromJSON ExampleDevice where
   parseJSON = withObject "ExampleDevice" $ \o -> do
     -- parse the field "model" from the JSON object
     model <- o .: "model" :: Parser Text
     case model of
       "ExampleDevice" -> ExampleDevice <$> (Pin <$> o .: "gpio")
       invalid         -> fail $ "Invalid model identifier: " ++ unpack invalid

 ```
