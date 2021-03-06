module Parser where

import           Control.Applicative                      ( pure )
import           Control.Monad                            ( ap
                                                          , liftM
                                                          , void
                                                          )
import           Data.List                                ( find )
import           Data.Maybe                               ( isJust )
-- import           Debug.Trace

newtype Parser a = Parser (String -> [(a, String)])

parse :: Parser t -> String -> [(t, String)]
parse (Parser p) = p

instance Functor Parser where
  fmap = liftM

instance Applicative Parser where
  pure  = return
  (<*>) = ap

instance Monad Parser where
  return a = Parser (\s -> [(a, s)])
  p >>= f = Parser (concatMap (\(a, s') -> parse (f a) s') . parse p)

item :: Parser Char
item = Parser item'
 where
  item' s = case s of
    ""       -> []
    (c : cs) -> [(c, cs)]

class Monad m => MonadPlus m where
  mzero :: m a
  mplus :: m a -> m a -> m a

instance MonadPlus Parser where
  mzero = Parser (const [])
  mplus p q = Parser (\s -> parse p s ++ parse q s)

option :: Parser a -> Parser a -> Parser a
option p q = Parser
  (\s -> case parse (mplus p q) s of
    []      -> []
    (x : _) -> [x]
  )

(<|>) :: Parser a -> Parser a -> Parser a
(<|>) = option

satisfies :: (Char -> Bool) -> Parser Char
satisfies p = item >>= \c -> if p c then return c else mzero

char :: Char -> Parser Char
char c = satisfies (c ==)

string :: String -> Parser String
string ""       = return ""
string (c : cs) = do
  _ <- char c
  _ <- string cs
  return (c : cs)

many :: Parser a -> Parser [a]
many p = many1 p <|> return []

many1 :: Parser a -> Parser [a]
many1 p = do
  a  <- p
  as <- many p
  return (a : as)

sepBy :: Parser a -> Parser b -> Parser [a]
p `sepBy` sep = (p `sepBy1` sep) <|> return []

sepBy1 :: Parser a -> Parser b -> Parser [a]
p `sepBy1` sep = do
  a  <- p
  as <- many
    (do
      _ <- sep
      p
    )
  return (a : as)

chainl :: Parser a -> Parser (a -> a -> a) -> a -> Parser a
chainl p op a = (p `chainl1` op) <|> return a

chainl1 :: Parser a -> Parser (a -> a -> a) -> Parser a
p `chainl1` op = do
  a <- p
  rest a
 where
  rest a =
    (do
        f <- op
        b <- p
        rest (f a b)
      )
      <|> return a

oneOf :: String -> Parser Char
oneOf cs = satisfies (`elem` cs)

noneOf :: String -> Parser Char
noneOf cs = satisfies (`notElem` cs)

manyN :: Parser a -> Int -> Parser [a]
manyN p 1 = do
  c <- p
  return [c]
manyN p n = do
  c    <- p
  rest <- manyN p (n - 1)
  return (c : rest)

manyTill :: Parser a -> Parser b -> Parser [a]
manyTill p end = manyTill1 p end <|> return []

manyTill1 :: Parser a -> Parser b -> Parser [a]
manyTill1 p end = do
  a <- p
  b <- lookAhead end
  if b
    then return [a]
    else do
      as <- manyTill p end
      return (a : as)

lookAhead :: Parser a -> Parser Bool
lookAhead p = Parser
  (\s -> case parse p s of
    [] -> [(False, s)]
    _  -> [(True, s)]
  )

-- | Lexical combinators
-- |
spaces :: Parser ()
spaces = void (many (satisfies isSpace))
 where
  isSpace ' '  = True
  isSpace '\n' = True
  isSpace '\r' = True
  isSpace '\t' = True
  isSpace _    = False

token :: Parser a -> Parser a
token p = do
  _ <- spaces
  a <- p
  _ <- spaces
  return a

symb :: String -> Parser String
symb s = token $ string s

digit :: Parser Char
digit = satisfies isDigit where isDigit c = isJust (find (== c) ['0' .. '9'])

numberInt :: Parser Int
numberInt = do
  sign   <- string "-" <|> string ""
  digits <- many1 digit
  return (read (sign ++ digits) :: Int)

numberDouble :: Parser Double
numberDouble = do
  sign     <- string "-" <|> string ""
  digits   <- many1 digit
  _        <- string "." <|> string ""
  mantissa <- many digit
  _        <- spaces
  let mantissa' = if mantissa == "" then "0" else mantissa
      double    = sign ++ digits ++ "." ++ mantissa'
  return (read double :: Double)

letter :: Parser Char
letter = satisfies isAlpha
 where
  isAlpha c = isJust (find (== c) letters)
  letters = ['a' .. 'z'] ++ ['A' .. 'Z']

firstLetter :: Parser Char
firstLetter = letter <|> oneOf "+-*/<>=!?§$%&@~´',:._"

wordLetter :: Parser Char
wordLetter = firstLetter <|> digit

newline :: Parser Char
newline = char '\n'

crlf :: Parser Char
crlf = char '\r' *> char '\n'

endOfLine :: Parser Char
endOfLine = newline <|> crlf

anyChar :: Parser Char
anyChar = satisfies (const True)

emptyQuot :: Parser String
emptyQuot = string "[]"

escapeNewLine :: Parser Char
escapeNewLine = do
  b <- lookAhead (string "\\\n")
  -- traceM $ "\nb: " ++ show b
  if b
    then do
      _ <- char '\\'
      char '\n'
    else mzero

nonEscape :: Parser Char
nonEscape = noneOf "\\\""

-- character :: Parser Char
-- character = nonEscape <|> escapeNewLine

quotedString :: Parser String
quotedString = do
  char '"'
  strings <- many (escapeNewLine <|> nonEscape)
  char '"'
  return strings

