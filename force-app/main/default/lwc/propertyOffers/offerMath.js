export const APPROVAL_THRESHOLD = 10;

function toCents(value) {
    return Math.round(Number(value) * 100);
}

/**
 * Percent the amount is below the asking price, rounded half-up (away from
 * zero) to one decimal place, matching Apex Decimal.divide(…, 1, HALF_UP).
 * Uses whole-cent integer math so there is no floating-point drift at the
 * rounding boundary. Returns null when it can't be computed.
 */
export function percentBelowAsking(askingPrice, amount) {
    if (
        askingPrice === null ||
        askingPrice === undefined ||
        amount === null ||
        amount === undefined ||
        amount === '' ||
        Number.isNaN(Number(amount)) ||
        Number(askingPrice) <= 0
    ) {
        return null;
    }
    const askingCents = toCents(askingPrice);
    const diffCents = askingCents - toCents(amount);
    const sign = diffCents < 0 ? -1 : 1;
    const tenths = Math.floor(
        (2 * Math.abs(diffCents) * 1000 + askingCents) / (2 * askingCents)
    );
    return (sign * tenths) / 10 || 0;
}

export function needsApproval(percentBelow) {
    return percentBelow !== null && percentBelow > APPROVAL_THRESHOLD;
}
