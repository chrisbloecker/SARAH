{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TemplateHaskell   #-}
--------------------------------------------------------------------------------
module Sarah.Middleware.Device.AC.Toshiba
  where
--------------------------------------------------------------------------------
import           Control.Concurrent    (forkIO)
import           Data.Bits             (Bits, testBit, xor, zeroBits)
import           Data.ByteString       (ByteString)
import           Data.Monoid           ((<>))
import           Import.DeriveJSON
import           Raspberry.GPIO
--------------------------------------------------------------------------------
import qualified Data.ByteString   as BS
import qualified Language.C.Inline as C
--------------------------------------------------------------------------------

data Temperature = T17 | T18 | T19 | T20 | T21 | T22 | T23 | T24 | T25 | T26 | T27 | T28 | T29 | T30
data Fan         = FanAuto | FanQuiet | FanVeryLow | FanLow | FanNormal | FanHigh | FanVeryHigh
data Mode        = ModeAuto | ModeCool | ModeDry | ModeFan | ModeOff
data Power       = PowerHigh | PowerEco

data Config = Config { temperature :: Temperature
                     , fan         :: Fan
                     , mode        :: Mode
                     , mpower      :: Maybe Power
                     }

instance ToBits Temperature where
  toBits T17 = 0x0
  toBits T18 = 0x1
  toBits T19 = 0x2
  toBits T20 = 0x3
  toBits T21 = 0x4
  toBits T22 = 0x5
  toBits T23 = 0x6
  toBits T24 = 0x7
  toBits T25 = 0x8
  toBits T26 = 0x9
  toBits T27 = 0xA
  toBits T28 = 0xB
  toBits T29 = 0xC
  toBits T30 = 0xD

instance ToBits Fan where
  toBits FanAuto     = 0x0
  toBits FanQuiet    = 0x2
  toBits FanVeryLow  = 0x4
  toBits FanLow      = 0x6
  toBits FanNormal   = 0x8
  toBits FanHigh     = 0xA
  toBits FanVeryHigh = 0xC

instance ToBits Mode where
  toBits ModeAuto = 0x0
  toBits ModeCool = 0x1
  toBits ModeDry  = 0x2
  toBits ModeFan  = 0x4
  toBits ModeOff  = 0x7

instance ToBits Power where
  toBits PowerHigh = 0x1
  toBits PowerEco  = 0x3

--------------------------------------------------------------------------------
deriveJSON jsonOptions ''Temperature
deriveJSON jsonOptions ''Fan
deriveJSON jsonOptions ''Mode
deriveJSON jsonOptions ''Power
deriveJSON jsonOptions ''Config
--------------------------------------------------------------------------------

C.context (C.baseCtx <> C.bsCtx)
C.include "irslinger.h"
C.include "<stdio.h>"

bitsToNibble :: (Bits a) => a -> ByteString
bitsToNibble b = BS.concat [ if testBit b 3 then "1" else "0"
                           , if testBit b 2 then "1" else "0"
                           , if testBit b 1 then "1" else "0"
                           , if testBit b 0 then "1" else "0"
                           ]


convert :: Config -> ByteString
convert Config{..} =
  let t = toBits temperature :: Int
      f = toBits fan         :: Int
      m = toBits mode        :: Int
      bits = case mpower of
               Nothing    -> let checksum = map (foldr xor zeroBits) [[t, f], [0x1, m   ]]
                             in [0xF, 0x2, 0x0, 0xD, 0x0, 0x3, 0xF, 0xC, 0x0, 0x1, t, 0x0, f, m, 0x0, 0x0        ] ++ checksum
               Just power -> let p        = toBits power :: Int
                                 checksum = map (foldr xor zeroBits) [[t, f], [0x9, m, p]]
                             in [0xF, 0x2, 0x0, 0xD, 0x0, 0x4, 0xF, 0xB, 0x0, 0x9, t, 0x0, f, m, 0x0, 0x0, 0x0, p] ++ checksum
  in BS.concat . map bitsToNibble $ bits


send :: Pin -> Config -> IO ()
send (Pin pin) config = do
  let bs = convert config
  res <- [C.block| int
           {
             int frequency = 38000;          // The frequency of the IR signal in Hz
             double dutyCycle = 0.5;         // The duty cycle of the IR signal. 0.5 means for every cycle,
                                             // the LED will turn on for half the cycle time, and off the other half

             int* codes = (int*) calloc(4 * $bs-len:bs + 7, sizeof(int));

             if (!codes)
             {
               printf("Memory allocation for sending IR signals failed!");
               return -1;
             }

             char c;
             int i
               , bsIdx = 0
               ;

             codes[bsIdx++] = 4380;
             codes[bsIdx++] = 4360;

             for (i = 0; i < $bs-len:bs; ++i)
               switch ($bs-ptr:bs[i])
               {
                  case '0':
                    codes[bsIdx++] = 550;
                    codes[bsIdx++] = 530;
                    break;
                  case '1':
                    codes[bsIdx++] = 550;
                    codes[bsIdx++] = 1600;
                    break;
                  default:
                    printf("Invalid character in bitstring: %c", $bs-ptr:bs[i]);
               }

             codes[bsIdx++] =  550;
             codes[bsIdx++] = 5470;
             codes[bsIdx++] = 4380;
             codes[bsIdx++] = 4360;

             for (i = 0; i < $bs-len:bs; ++i)
               switch ($bs-ptr:bs[i])
               {
                 case '0':
                   codes[bsIdx++] = 550;
                   codes[bsIdx++] = 530;
                   break;
                 case '1':
                   codes[bsIdx++] = 550;
                   codes[bsIdx++] = 1600;
                   break;
                 default:
                   printf("Invalid character in bitstring: %c", c);
               }

             codes[bsIdx++] = 550;

             int result = irSlingRaw( $(int pin)
                                    , frequency
                                    , dutyCycle
                                    , codes
                                    , bsIdx
                                    );

             if (codes)
               free(codes);

             return result;
           }
         |]
  return ()