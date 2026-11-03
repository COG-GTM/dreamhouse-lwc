import { LightningElement, api, wire } from 'lwc';
import {
    getRecord,
    getFieldValue,
    notifyRecordUpdateAvailable
} from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOfferContext from '@salesforce/apex/OfferController.getOfferContext';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import approveOffer from '@salesforce/apex/OfferController.approveOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';
import rejectOffer from '@salesforce/apex/OfferController.rejectOffer';
import PRICE_FIELD from '@salesforce/schema/Property__c.Price__c';
import STATUS_FIELD from '@salesforce/schema/Property__c.Status__c';

const DEFAULT_THRESHOLD = 10;
const OPEN_STATUSES = ['Submitted', 'Needs Approval', 'Approved'];
const CLOSED_PROPERTY_STATUSES = ['Under Agreement', 'Contracted', 'Closed'];
const BADGE_CLASSES = {
    Submitted: 'slds-badge',
    'Needs Approval': 'slds-badge slds-theme_warning',
    Approved: 'slds-badge slds-badge_inverse',
    Accepted: 'slds-badge slds-theme_success',
    Rejected: 'slds-badge slds-theme_error'
};

/**
 * Percent below asking in tenths of a percent, rounded half-up (away from zero)
 * on exact integer cents, matching Apex setScale(1, RoundingMode.HALF_UP).
 */
function formatPercent(value) {
    const number = Number(value);
    return `${Math.abs(number).toFixed(1)}% ${number < 0 ? 'above' : 'below'} asking`;
}

function offerPercentText(row) {
    const current = row.percentBelowAsking;
    if (current === null || current === undefined) {
        return '';
    }
    const submitted = row.submittedPercentBelowAsking;
    if (
        submitted === null ||
        submitted === undefined ||
        Number(submitted) === Number(current)
    ) {
        return formatPercent(current);
    }
    return `${formatPercent(current)} (${formatPercent(submitted)} when submitted)`;
}

export function percentBelowTenths(askingPrice, amount) {
    const askingCents = Math.round(Number(askingPrice) * 100);
    const amountCents = Math.round(Number(amount) * 100);
    if (!(askingCents > 0) || !Number.isFinite(amountCents)) {
        return null;
    }
    const numerator = (askingCents - amountCents) * 1000;
    const magnitude = Math.floor(
        (2 * Math.abs(numerator) + askingCents) / (2 * askingCents)
    );
    return numerator < 0 ? -magnitude : magnitude;
}

function errorMessage(error) {
    return error?.body?.message || error?.message || 'Unknown error';
}

export default class PropertyOffers extends LightningElement {
    buyerName = '';
    amount;
    context;
    error;
    isBusy = false;

    _recordId;
    _requestId = 0;
    _recordFieldsKey;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value === this._recordId) {
            return;
        }
        this._recordId = value;
        this.buyerName = '';
        this.amount = undefined;
        this.context = undefined;
        this._recordFieldsKey = undefined;
        this.loadOffers();
    }

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [PRICE_FIELD, STATUS_FIELD]
    })
    wiredProperty({ data }) {
        if (!data) {
            return;
        }
        const price = getFieldValue(data, PRICE_FIELD);
        const status = getFieldValue(data, STATUS_FIELD);
        const key = `${price}|${status}`;
        const changed =
            this._recordFieldsKey !== undefined &&
            this._recordFieldsKey !== key;
        this._recordFieldsKey = key;
        const stale =
            this.context &&
            (this.context.askingPrice !== price ||
                this.context.propertyStatus !== status);
        if (changed || stale) {
            this.loadOffers();
        }
    }

    get cardTitle() {
        return `Offers (${this.offers.length})`;
    }

    get askingPrice() {
        return this.context?.askingPrice;
    }

    get threshold() {
        return this.context?.approvalThreshold ?? DEFAULT_THRESHOLD;
    }

    get propertyOpen() {
        return (
            !!this.context &&
            !CLOSED_PROPERTY_STATUSES.includes(this.context.propertyStatus)
        );
    }

    get propertyClosedMessage() {
        return this.context && !this.propertyOpen
            ? `Offers are closed: the property is ${this.context.propertyStatus}.`
            : null;
    }

    get previewTenths() {
        if (
            this.amount === undefined ||
            this.amount === null ||
            this.amount === ''
        ) {
            return null;
        }
        return percentBelowTenths(this.askingPrice, this.amount);
    }

    get hasPreview() {
        return this.previewTenths !== null && Number(this.amount) > 0;
    }

    get previewNeedsApproval() {
        return this.hasPreview && this.previewTenths > this.threshold * 10;
    }

    get previewText() {
        if (!this.hasPreview) {
            return '';
        }
        const tenths = this.previewTenths;
        const percent = (Math.abs(tenths) / 10).toFixed(1);
        const direction = tenths < 0 ? 'above' : 'below';
        return this.previewNeedsApproval
            ? `${percent}% ${direction} asking, needs broker approval`
            : `${percent}% ${direction} asking`;
    }

    get previewClass() {
        return this.previewNeedsApproval
            ? 'slds-text-color_error slds-m-bottom_small'
            : 'slds-text-color_weak slds-m-bottom_small';
    }

    get submitDisabled() {
        return (
            this.isBusy ||
            !this.propertyOpen ||
            !this.buyerName.trim() ||
            !(Number(this.amount) > 0)
        );
    }

    get offers() {
        const rows = this.context?.offers || [];
        const open = this.propertyOpen;
        const canApprove = !!this.context?.canApprove;
        return rows.map((row) => {
            const isOpen = open && OPEN_STATUSES.includes(row.status);
            return {
                ...row,
                badgeClass: BADGE_CLASSES[row.status] || 'slds-badge',
                showApprove: isOpen && canApprove && row.requiresApproval,
                showAccept: isOpen && !row.requiresApproval,
                showReject: isOpen,
                showApprovalHint: isOpen && !canApprove && row.requiresApproval,
                percentText: offerPercentText(row),
                approveTitle: `Approve offer from ${row.buyerName}`,
                acceptTitle: `Accept offer from ${row.buyerName}`,
                rejectTitle: `Reject offer from ${row.buyerName}`
            };
        });
    }

    get hasOffers() {
        return this.offers.length > 0;
    }

    async loadOffers(isRetry = false) {
        const recordId = this._recordId;
        const requestId = ++this._requestId;
        if (!recordId) {
            return;
        }
        try {
            const context = await getOfferContext({ propertyId: recordId });
            if (requestId !== this._requestId) {
                return;
            }
            this.context = context;
            this.error = undefined;
            const key = `${context?.askingPrice}|${context?.propertyStatus}`;
            if (
                !isRetry &&
                this._recordFieldsKey !== undefined &&
                this._recordFieldsKey !== key
            ) {
                this.loadOffers(true);
            }
        } catch (error) {
            if (requestId === this._requestId) {
                this.error = errorMessage(error);
            }
        }
    }

    handleBuyerChange(event) {
        this.buyerName = event.target.value || '';
    }

    handleAmountChange(event) {
        this.amount = event.target.value;
    }

    async handleSubmit() {
        const buyerName = this.buyerName.trim();
        const amount = Number(this.amount);
        const ok = await this.runAction(
            () =>
                submitOffer({
                    propertyId: this._recordId,
                    buyerName,
                    amount
                }),
            `Offer from ${buyerName} submitted`
        );
        if (ok) {
            this.buyerName = '';
            this.amount = undefined;
        }
    }

    handleApprove(event) {
        const { id, buyer } = event.target.dataset;
        this.runAction(
            () => approveOffer({ propertyId: this._recordId, offerId: id }),
            `Offer from ${buyer} approved`
        );
    }

    handleAccept(event) {
        const { id, buyer } = event.target.dataset;
        this.runAction(
            () => acceptOffer({ propertyId: this._recordId, offerId: id }),
            `Offer from ${buyer} accepted`,
            true
        );
    }

    handleReject(event) {
        const { id, buyer } = event.target.dataset;
        this.runAction(
            () => rejectOffer({ propertyId: this._recordId, offerId: id }),
            `Offer from ${buyer} rejected`
        );
    }

    async runAction(action, successMessage, propertyChanged = false) {
        const recordId = this._recordId;
        const requestId = ++this._requestId;
        this.isBusy = true;
        try {
            const context = await action();
            if (requestId === this._requestId && recordId === this._recordId) {
                this.context = context;
                this.error = undefined;
            }
            this.dispatchEvent(
                new ShowToastEvent({
                    title: successMessage,
                    variant: 'success'
                })
            );
            if (propertyChanged) {
                notifyRecordUpdateAvailable([{ recordId }]);
            }
            return true;
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Offer not saved',
                    message: errorMessage(error),
                    variant: 'error'
                })
            );
            return false;
        } finally {
            this.isBusy = false;
        }
    }
}
