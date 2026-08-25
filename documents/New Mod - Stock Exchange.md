# Transport Fever 2 — Stock Exchange Mod Concept

## Core idea

Add a lightweight **stock exchange and corporate-finance layer** to *Transport Fever 2*.

The player can invest in the **actual industries operating on their map**, with company values driven primarily by how those industries perform in the real simulation.

At the same time, the player's own transport company can be publicly listed, allowing the player to raise money by selling shares — at the cost of giving outside shareholders a portion of future profits.

The basic philosophy is:

> **The transport network creates the economy, and the stock market reflects it.**

The mod should add another strategic layer without replacing or interfering with the core transport gameplay.

---

## 1. Every industry becomes a company

Existing map industries become fictional listed companies.

For example:

```text
HENDON GRAIN COMPANY

Share Price             $14.82
Shares Outstanding     100,000
Market Capitalisation  $1,482,000

Production                 187
Shipment                   184
Transport                  96%

Your Shares              8,000
Your Ownership             8.0%
Holding Value          $118,560

[ BUY ]       [ SELL ]
```

The company is attached to the **real TF2 industry entity**, rather than being a randomly generated company unrelated to the map.

---

## 2. Industry performance drives share prices

Share prices shouldn't simply rise randomly.

The valuation system should use actual game information where available, such as:

* production;
* shipment;
* transport percentage;
* production capacity;
* input availability;
* output movement;
* industry growth/level;
* historical performance.

An industry that produces heavily and successfully ships almost everything should generally outperform an industry whose goods sit around untransported.

This creates the central gameplay loop:

```text
Buy shares in industry
        ↓
Improve its transport network
        ↓
More inputs arrive
        ↓
More goods produced
        ↓
More goods transported
        ↓
Company performs better
        ↓
Share value increases
```

The player therefore has an unusual advantage as an investor:

**they operate the transport network serving the companies they're investing in.**

---

## 3. Historical inflation

Companies need sensible nominal growth across TF2's enormous 1850→modern timeline.

A configurable historical inflation assumption — perhaps around **4% annually as an initial balancing experiment** — could influence nominal prices.

However, inflation should **not guarantee a 4% investment return**.

A badly performing company could appreciate more slowly than inflation or actually lose nominal value.

For example:

```text
Base economic/inflation trend
        +
Real industry performance
        +
Growth expectations
        +
Corporate events
        =
Share valuation
```

The economy therefore grows naturally over 150+ years without making every investment an automatic winner.

---

## 4. Player's transport company can also be listed

This could become one of the strongest features.

Rather than the player simply starting with TF2's normal bank financing, the mod could introduce **equity capital**.

Example starting position:

```text
EPOD TRANSPORT LTD — 1850

Founder ownership          51%
Public ownership           49%

Equity capital raised   $1.0m
Bank loan               $5.0m
─────────────────────────────
Starting capital        $6.0m
```

The exact numbers would need balancing and compatibility with the selected difficulty.

The important concept is that the player now has two major external sources of finance:

**Debt**

> Borrow money → receive capital now → pay interest.

**Equity**

> Sell shares → receive capital now → surrender some future profits.

---

## 5. Issue additional shares

The player could raise capital without increasing bank debt.

For example:

```text
NEW SHARE ISSUE

Current shares          100,000
Your shares              51,000
Current ownership           51%

Issue                     25,000
Capital raised        $2,500,000

New shares outstanding   125,000
Your new ownership         40.8%

[ CANCEL ]       [ ISSUE ]
```

This creates a genuine strategic decision.

Need $2.5m immediately to build a railway?

The player can borrow it or sell part of the company.

Selling shares isn't free money because those shareholders now participate in future dividends.

---

## 6. Ownership can fall all the way to 0%

There should be **no game-over condition for losing majority ownership**.

The player could theoretically sell 100% of their transport company and continue operating it.

That creates an aggressive financing strategy:

> Sell most/all of the company early → obtain enormous expansion capital → build infrastructure much sooner → deal with the long-term financial consequences.

The player remains effectively the permanent operator/CEO for gameplay purposes.

No shareholder voting, hostile takeovers or getting fired is necessary.

---

# 7. Dividends provide the reason to own yourself

Ownership doesn't need arbitrary gameplay bonuses.

Its value is simple:

> **The more of your company outsiders own, the more of your profits leave the company as dividends.**

Suppose:

```text
Annual Profit             $20m
Dividend Payout Ratio       40%
Dividend Pool               $8m
```

At 51% player ownership:

```text
Player ownership             51%
External ownership           49%

Player economic share      $4.08m
External dividend          $3.92m
```

Because TF2 doesn't have separate personal and corporate wallets, the player's own dividend doesn't actually need to be paid out.

Only the **external shareholder portion** needs to leave the company's account.

Conceptually:

```text
External Dividend =
Annual Profit
× Dividend Payout Ratio
× External Ownership %
```

---

## 8. The long-term objective: buy yourself back

This gives late-game money a new purpose.

The player might sell shares aggressively during early expansion:

```text
1850     51%
1860     43%
1870     31%
1880     22%
```

Once the network becomes extremely profitable, they begin buying shares back:

```text
1900     30%
1920     48%
1950     67%
1980     89%
2000    100%
```

At 100%:

```text
PRIVATE OWNERSHIP RESTORED

Your Ownership              100%
External Ownership             0%

External Dividend Obligation  $0
```

There doesn't need to be a magical reward.

**Keeping 100% of future profits is the reward.**

There's also a natural catch: if the player builds a fantastic transport empire, their own shares become increasingly expensive.

Shares sold cheaply in 1850 could cost a fortune to repurchase in 1950.

---

# 9. Corporate actions and random events

Companies shouldn't behave completely predictably.

A controlled event system could create occasional corporate events.

Examples include:

**Stock split**

```text
2-FOR-1 STOCK SPLIT

Before:
10,000 shares × $80 = $800,000

After:
20,000 shares × $40 = $800,000
```

No immediate change in wealth.

**New share issue**

The company raises capital by issuing additional shares.

Existing shareholders are diluted and the share price may initially decline, while the company receives an expansion/growth benefit.

**Special dividend**

A highly successful company returns excess profits to shareholders.

**Factory modernisation**

Short-term cost or reduced dividend followed by improved growth prospects.

**Supply shortage**

Poor input deliveries hurt company performance.

**Export boom**

Very high production and transport performance improves sentiment/value.

Other possibilities include recessions, accidents, strikes, takeover rumours and exceptional production years.

Random events should be secondary to actual game performance — perhaps roughly **70–80% fundamentals and 20–30% events/market variation**, subject to balancing.

The player should never feel that excellent transport management is irrelevant because RNG controls everything.

---

# 10. Stock Exchange GUI

A central exchange window could eventually contain tabs such as:

```text
STOCK EXCHANGE

[ MARKET ]
[ PORTFOLIO ]
[ MY COMPANY ]
[ NEWS ]
[ HISTORY ]
```

### Market

```text
COMPANY                 PRICE      CHANGE    TRANSPORT

Hendon Grain Co.        $18.42      +3.8%       96%
Alexander Oil Ltd.      $31.20      -1.4%       72%
Grove Steel Works       $44.81      +6.1%       99%
Queens Food Co.         $12.08      +0.3%       84%
```

Selecting one opens its company page and Buy/Sell controls.

### Portfolio

```text
COMPANY             SHARES       VALUE       RETURN

Hendon Grain          5,000      $284,500      +138%
Alexander Oil         2,000      $193,200       +46%
Queens Food           8,000      $112,640       +11%

TOTAL                            $590,340       +72%
```

### My Company

Shows:

```text
EPOD TRANSPORT LTD

Share Price
Market Capitalisation
Shares Outstanding
Your Ownership
External Ownership
Annual Profit
Dividend Rate
External Dividend Cost

[ ISSUE SHARES ]
[ BUY SHARES ]
```

---

# 11. Financial transactions should affect real TF2 money

Buying shares should remove actual company cash.

Selling shares should add actual company cash.

Issuing shares in the player's company should raise actual cash.

External dividends should remove actual cash.

The initial technical research indicates TF2's `bookJournalEntry` command may provide the mechanism for posting these financial transactions, but this should be **live-tested before development relies upon it**.

Ideally transactions would also appear naturally in TF2's financial records.

---

# 12. Persistence

The mod would need to persist its own market state, including things such as:

```text
Industry/company ID
Share price
Shares outstanding
Player shares
Price history
Corporate events
Company valuation history

Player company:
Shares outstanding
Player ownership
Public ownership
Dividend policy
Share price/history
```

Industry entities would provide the underlying economic performance; the mod supplies the financial-market abstraction layered over them.

---

# 13. Suggested development stages

**V0.1 — Proof of concept**

Prove two things:

1. TF2 industry performance statistics can be read reliably.
2. Money can safely be added/subtracted from the player's real account.

If either fails, reassess the design before doing substantial work.

**V0.2 — Industry Exchange**

Create listed companies from actual industries, calculate valuations and allow Buy/Sell transactions with persistence.

**V0.3 — Player Company**

Add player-company shares, starting ownership, share issuance, dilution, buybacks and annual dividends.

**V0.4 — Market depth**

Add price histories, portfolio returns, company information and corporate events.

**V1.0 — Polished Exchange**

Balance the economy across long games, finish native TF2 GUI, add market news/history, save/load reliability and compatibility testing.

---

## Overall design principle

The Stock Exchange shouldn't become a completely separate financial game bolted onto TF2.

Its strongest feature is that **everything ultimately comes back to transport**:

> Buy a struggling industry because you think you can connect it better.

> Invest in a producer whose output you expect to explode.

> Sell part of your transport company to finance a massive railway.

> Pay outside shareholders for decades because you diluted yourself too heavily.

> Eventually use your successful transport empire to buy the company back.

In short:

> **Build the network. Grow the industries. Invest in their success. Finance your expansion. Eventually own your empire.**

And compared with DD, the architecture should be considerably simpler because the Stock Exchange would primarily **observe TF2 and maintain its own economic simulation**, rather than continually intervening in vehicle movement, routing and line allocation.
