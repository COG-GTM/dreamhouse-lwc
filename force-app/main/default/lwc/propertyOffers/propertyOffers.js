import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import PRICE_FIELD from '@salesforce/schema/Property__c.Price__c';
import STATUS_FIELD from '@salesforce/schema/Property__c.Status__c';
import { reduceErrors } from 'c/ldsUtils';
import getOfferContext from '@salesforce/apex/OfferController.getOfferContext';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import approveOffer from '@salesforce/apex/OfferController.approveOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';
import rejectOffer from '@salesforce/apex/OfferController.rejectOffer';

const STATUS = {
    SUBMITTED: 'Submitted',
    NEEDS_APPROVAL: 'Needs Approval',
    APPROVED: 'Approved',
    ACCEPTED: 'Accepted',
    REJECTED: 'Rejected'
};
const OPEN_STATUSES = [
    STATUS.SUBMITTED,
    STATUS.NEEDS_APPROVAL,
    STATUS.APPROVED
];
const BADGE_CLASSES = {
    [STATUS.SUBMITTED]: 'slds-badge_lightest',
    [STATUS.NEEDS_APPROVAL]: 'slds-theme_warning',
    [STATUS.APPROVED]: 'slds-badge_inverse',
    [STATUS.ACCEPTED]: 'slds-theme_success',
    [STATUS.REJECTED]: 'slds-theme_error'
};
const ACTIONS = {
    approve: { apex: approveOffer, verb: 'approved' },
    accept: { apex: acceptOffer, verb: 'accepted' },
    reject: { apex: rejectOffer, verb: 'rejected' }
};
const DEFAULT_THRESHOLD = 10;

/**
 * % below asking rounded half-up to one decimal place, matching
 * OfferService.percentBelowAsking in Apex. Works in whole cents with integer
 * arithmetic so the 10% boundary is exact.
 */
export function percentBelowAsking(askingPrice, amount) {
    const askingCents = Math.round(askingPrice * 100);
    const amountCents = Math.round(amount * 100);
    if (!(askingCents > 0)) {
        return null;
    }
    const diff = askingCents - amountCents;
    const numerator = 2000 * Math.abs(diff) + askingCents;
    const denominator = 2 * askingCents;
    const tenths = (numerator - (numerator % denominator)) / denominator;
    return ((diff < 0 ? -tenths : tenths) || 0) / 10;
}

export default class PropertyOffers extends LightningElement {
    _recordId;
    context;
    error;
    buyerName = '';
    amount;
    isWorking = false;
    requestCounter = 0;
    propertyVersion;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const changed = value !== this._recordId;
        this._recordId = value;
        if (changed && value) {
            this.buyerName = '';
            this.amount = undefined;
            this.propertyVersion = undefined;
            this.context = undefined;
            this.loadOffers();
        }
    }

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [PRICE_FIELD, STATUS_FIELD]
    })
    wiredProperty({ data }) {
        if (!data) {
            return;
        }
        const version = [PRICE_FIELD, STATUS_FIELD]
            .map(({ fieldApiName }) => data.fields[fieldApiName]?.value)
            .join('|');
        if (
            this.propertyVersion !== undefined &&
            version !== this.propertyVersion
        ) {
            this.loadOffers();
        }
        this.propertyVersion = version;
    }

    async loadOffers() {
        const requestId = ++this.requestCounter;
        const propertyId = this._recordId;
        try {
            const context = await getOfferContext({ propertyId });
            if (requestId !== this.requestCounter) {
                return;
            }
            this.context = context;
            this.error = undefined;
        } catch (error) {
            if (requestId !== this.requestCounter) {
                return;
            }
            this.context = undefined;
            this.error = error;
        }
    }

    get isLoaded() {
        return Boolean(this.context);
    }

    get offers() {
        const context = this.context;
        if (!context || !context.offers) {
            return [];
        }
        return context.offers.map((offer) => {
            const isOpen = OPEN_STATUSES.includes(offer.Status__c);
            return {
                ...offer,
                badgeClass: BADGE_CLASSES[offer.Status__c] || '',
                showApprove:
                    context.propertyOpen &&
                    context.canApprove &&
                    offer.Status__c === STATUS.NEEDS_APPROVAL,
                showAccept:
                    context.propertyOpen &&
                    (offer.Status__c === STATUS.SUBMITTED ||
                        offer.Status__c === STATUS.APPROVED),
                showReject: isOpen,
                approveTitle: `Approve offer from ${offer.Buyer_Name__c}`,
                acceptTitle: `Accept offer from ${offer.Buyer_Name__c}`,
                rejectTitle: `Reject offer from ${offer.Buyer_Name__c}`,
                percentLabel: this.formatPercent(offer.Percent_Below_Asking__c)
            };
        });
    }

    get hasOffers() {
        return this.offers.length > 0;
    }

    get cardTitle() {
        return `Offers (${this.offers.length})`;
    }

    get propertyOpen() {
        return Boolean(this.context && this.context.propertyOpen);
    }

    get closedMessage() {
        return `This property is ${this.context.propertyStatus} and is no longer taking offers.`;
    }

    get threshold() {
        const threshold = this.context && this.context.approvalThreshold;
        return threshold === undefined || threshold === null
            ? DEFAULT_THRESHOLD
            : threshold;
    }

    get previewPercent() {
        const amount = Number(this.amount);
        if (!this.context || !(amount > 0)) {
            return null;
        }
        return percentBelowAsking(this.context.askingPrice, amount);
    }

    get hasPreview() {
        return this.previewPercent !== null;
    }

    get previewNeedsApproval() {
        return this.hasPreview && this.previewPercent > this.threshold;
    }

    get previewText() {
        const label = this.formatPercent(this.previewPercent);
        return this.previewNeedsApproval
            ? `${label}, needs broker approval`
            : label;
    }

    get previewClass() {
        return this.previewNeedsApproval
            ? 'slds-text-color_error slds-text-title_bold'
            : 'slds-text-color_weak';
    }

    get submitDisabled() {
        return (
            this.isWorking ||
            !this.buyerName.trim() ||
            !(Number(this.amount) > 0)
        );
    }

    formatPercent(value) {
        if (value === null || value === undefined) {
            return '';
        }
        const number = Number(value);
        return number < 0
            ? `${Math.abs(number).toFixed(1)}% above asking`
            : `${number.toFixed(1)}% below asking`;
    }

    handleBuyerChange(event) {
        this.buyerName = event.target.value || '';
    }

    handleAmountChange(event) {
        this.amount = event.target.value;
    }

    async handleSubmit() {
        if (this.submitDisabled) {
            return;
        }
        this.isWorking = true;
        try {
            const offer = await submitOffer({
                propertyId: this._recordId,
                buyerName: this.buyerName,
                amount: Number(this.amount)
            });
            this.buyerName = '';
            this.amount = undefined;
            const needsApproval = offer.Status__c === STATUS.NEEDS_APPROVAL;
            this.toast(
                needsApproval
                    ? 'Offer needs broker approval'
                    : 'Offer submitted',
                `${offer.Buyer_Name__c}'s offer is ${offer.Status__c}.`,
                needsApproval ? 'warning' : 'success'
            );
            await this.loadOffers();
        } catch (error) {
            this.toast(
                'Could not submit offer',
                reduceErrors(error).join(', '),
                'error'
            );
        } finally {
            this.isWorking = false;
        }
    }

    async handleAction(event) {
        const { id, action } = event.currentTarget.dataset;
        const config = ACTIONS[action];
        if (!config) {
            return;
        }
        this.isWorking = true;
        try {
            await config.apex({ offerId: id });
            this.toast(`Offer ${config.verb}`, '', 'success');
            await this.loadOffers();
            if (action === 'accept') {
                await notifyRecordUpdateAvailable([
                    { recordId: this._recordId }
                ]);
            }
        } catch (error) {
            this.toast(
                `Could not ${action} offer`,
                reduceErrors(error).join(', '),
                'error'
            );
            await this.loadOffers();
        } finally {
            this.isWorking = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
