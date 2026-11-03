// Which cosmetic the profile drawings wear. An earned skin wins over a shop skin.
// Balances are bigints in index order. Unknown indexes still get a label.

export function ownedEntries(balances, catalog, source) {
  const owned = [];
  balances.forEach((balance, index) => {
    if (balance > 0n) {
      const known = catalog[index];
      owned.push({
        index,
        balance,
        name: known?.name ?? `${source} ${index}`,
        color: known?.color ?? "#8a8175",
        source,
      });
    }
  });
  return owned;
}

export function selectWornSkin(paidBalances, earnedBalances, paidCatalog, earnedCatalog) {
  const earned = ownedEntries(earnedBalances, earnedCatalog, "Earned");
  if (earned.length > 0) return earned[0];
  const paid = ownedEntries(paidBalances, paidCatalog, "Shop");
  if (paid.length > 0) return paid[0];
  return null;
}
