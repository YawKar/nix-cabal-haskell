module Main (main) where

import Lib2 (shout)
import Test.Hspec

main :: IO ()
main = hspec $ do
    describe "shout" $ do
        it "upper-cases the greeting" $
            shout "world" `shouldBe` "HELLO, WORLD!"
