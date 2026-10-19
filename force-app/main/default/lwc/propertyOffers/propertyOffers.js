import { LightningElement, api, wire } from 'lwc';
import {
    getRecord,
    getFieldValue,
    notifyRecordUpdateAvailable
} from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceErrors } from 'c/ldsUtils';
import getOfferContext from '@salesforce/apex/OfferController.getOfferContext';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import approveOffer from '@salesforce/apex/OfferController.approveOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';
import rejectOffer from '@salesforce/apex/OfferController.rejectOffer';

import PRICE_FIELD from '@salesforce/schema/Property__c.Price__c';
import STATUS_FIELD from '@salesforce/schema/Property__c.Status__c';

export const APPROVAL_THRESHOLD = 10;
const CLOSED_PROPERTY_STATUSES = ['Under Agreement', 'Contracted', 'Closed'];
const OPEN_OFFER_STATUSES = ['Submitted', 'Needs Approval', 'Approved'];
const BADGE_CLASSES = {
    Submitted: 'slds-badge',
    'Needs Approval': 'slds-badge slds-theme_warning',
    Approved: 'slds-badge slds-badge_inverse',
    Accepted: 'slds-badge slds-theme_success',
    Rejected: 'slds-badge slds-theme_error'
};

/**
 * Mirrors OfferService.percentBelowAsking: one decimal place, half-up,
 * so the preview agrees with Apex at the 10% boundary.
 */
export function percentBelowAsking(askingPrice, amount) {
    if (!askingPrice || askingPrice <= 0 || amount === null || amount === '') {
        return null;
    }
    const value = Number(amount);
    if (Number.isNaN(value)) {
        return null;
    }
    // Whole cents and integer math keep the half-up rounding exact, like
    // Apex Decimal arithmetic.
    const askingCents = Math.round(askingPrice * 100);
    const amountCents = Math.round(value * 100);
    const numerator = Math.abs(askingCents - amountCents) * 2000 + askingCents;
    const denominator = askingCents * 2;
    let tenths = Math.floor(numerator / denominator);
    if (tenths * denominator > numerator) {
        tenths -= 1;
    } else if ((tenths + 1) * denominator <= numerator) {
        tenths += 1;
    }
    const rounded = tenths / 10;
    return amountCents > askingCents && rounded !== 0 ? -rounded : rounded;
}

export default class PropertyOffers extends LightningElement {
    _recordId;
    isConnected = false;
    loadSequence = 0;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value === this._recordId) {
            return;
        }
        this._recordId = value;
        this.offers = [];
        this.canApprove = false;
        this.loadError = undefined;
        this.buyerName = '';
        this.amount = null;
        if (this.isConnected) {
            this.loadOffers();
        }
    }

    offers = [];
    canApprove = false;
    buyerName = '';
    amount = null;
    isBusy = false;
    loadError;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [PRICE_FIELD, STATUS_FIELD]
    })
    property;

    connectedCallback() {
        this.isConnected = true;
        this.loadOffers();
    }

    disconnectedCallback() {
        this.isConnected = false;
    }

    get askingPrice() {
        return getFieldValue(this.property?.data, PRICE_FIELD);
    }

    get propertyStatus() {
        return getFieldValue(this.property?.data, STATUS_FIELD);
    }

    get isPropertyClosed() {
        return CLOSED_PROPERTY_STATUSES.includes(this.propertyStatus);
    }

    get cardTitle() {
        return `Offers (${this.offers.length})`;
    }

    get hasOffers() {
        return this.offers.length > 0;
    }

    get noOffersYet() {
        return !this.loadError;
    }

    get previewPercent() {
        return percentBelowAsking(this.askingPrice, this.amount);
    }

    get hasPreview() {
        return this.previewPercent !== null && Number(this.amount) > 0;
    }

    get previewNeedsApproval() {
        return this.hasPreview && this.previewPercent > APPROVAL_THRESHOLD;
    }

    get previewText() {
        const percent = this.previewPercent;
        if (percent < 0) {
            return `${Math.abs(percent).toFixed(1)}% above asking`;
        }
        const text = `${percent.toFixed(1)}% below asking`;
        return this.previewNeedsApproval
            ? `${text}, needs broker approval`
            : text;
    }

    get previewClass() {
        return this.previewNeedsApproval
            ? 'slds-text-color_error slds-text-body_small'
            : 'slds-text-color_weak slds-text-body_small';
    }

    get submitDisabled() {
        return (
            this.isBusy ||
            this.isPropertyClosed ||
            !this.buyerName.trim() ||
            !(Number(this.amount) > 0)
        );
    }

    get offerRows() {
        const propertyOpen = !this.isPropertyClosed;
        return this.offers.map((offer) => {
            const status = offer.Status__c;
            const isOpen = OPEN_OFFER_STATUSES.includes(status);
            // Mirrors acceptOffer: a Submitted offer that the current asking
            // price puts more than 10% below asking can't be accepted.
            const needsResubmit =
                status === 'Submitted' &&
                percentBelowAsking(this.askingPrice, offer.Amount__c) >
                    APPROVAL_THRESHOLD;
            return {
                ...offer,
                percentLabel: this.formatPercent(offer.Percent_Below_Asking__c),
                badgeClass: BADGE_CLASSES[status] || 'slds-badge',
                showApprove:
                    this.canApprove &&
                    propertyOpen &&
                    status === 'Needs Approval',
                showAccept:
                    propertyOpen &&
                    !needsResubmit &&
                    (status === 'Submitted' || status === 'Approved'),
                showResubmitNote: propertyOpen && needsResubmit,
                showReject: isOpen,
                approveLabel: `Approve offer from ${offer.Buyer_Name__c}`,
                acceptLabel: `Accept offer from ${offer.Buyer_Name__c}`,
                rejectLabel: `Reject offer from ${offer.Buyer_Name__c}`
            };
        });
    }

    formatPercent(value) {
        if (value === null || value === undefined) {
            return '';
        }
        return value < 0
            ? `${Math.abs(value).toFixed(1)}% above asking`
            : `${Number(value).toFixed(1)}% below asking`;
    }

    async loadOffers() {
        const propertyId = this.recordId;
        if (!propertyId) {
            return;
        }
        // Only the latest request may update the card, so a slow earlier
        // response can't overwrite fresher offers or another property's.
        const request = ++this.loadSequence;
        try {
            const context = await getOfferContext({ propertyId });
            if (request !== this.loadSequence) {
                return;
            }
            this.offers = context.offers || [];
            this.canApprove = context.canApprove === true;
            this.loadError = undefined;
        } catch (error) {
            if (request !== this.loadSequence) {
                return;
            }
            this.loadError = error;
            this.offers = [];
        }
    }

    handleBuyerChange(event) {
        this.buyerName = event.target.value || '';
    }

    handleAmountChange(event) {
        const value = event.target.value;
        this.amount = value === '' || value === null ? null : Number(value);
    }

    async handleSubmit() {
        const succeeded = await this.runAction(
            () =>
                submitOffer({
                    propertyId: this.recordId,
                    buyerName: this.buyerName,
                    amount: this.amount
                }),
            'Offer submitted'
        );
        if (succeeded) {
            this.buyerName = '';
            this.amount = null;
        }
    }

    handleApprove(event) {
        return this.runAction(
            () => approveOffer({ offerId: event.target.dataset.id }),
            'Offer approved'
        );
    }

    async handleAccept(event) {
        const succeeded = await this.runAction(
            () => acceptOffer({ offerId: event.target.dataset.id }),
            'Offer accepted. Property is now Under Agreement.'
        );
        if (succeeded) {
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        }
    }

    handleReject(event) {
        return this.runAction(
            () => rejectOffer({ offerId: event.target.dataset.id }),
            'Offer rejected'
        );
    }

    async runAction(action, successMessage) {
        this.isBusy = true;
        try {
            await action();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: successMessage,
                    variant: 'success'
                })
            );
            await this.loadOffers();
            return true;
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Offer not updated',
                    message: reduceErrors(error).join(', '),
                    variant: 'error'
                })
            );
            return false;
        } finally {
            this.isBusy = false;
        }
    }
}
