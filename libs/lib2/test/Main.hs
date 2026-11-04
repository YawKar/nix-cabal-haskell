module Main (main) where

import Test.Hspec qualified as Hspec

import Lib2 qualified (shout)

main :: IO ()
main = Hspec.hspec $ do
    Hspec.describe "shout" $ do
        Hspec.it "upper-cases the greeting" $
            Lib2.shout "world" `Hspec.shouldBe` "HELLO, WORLD!"
