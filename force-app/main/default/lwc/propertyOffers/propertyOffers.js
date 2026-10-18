import { LightningElement, api, wire } from 'lwc';
import {
    getRecord,
    getFieldValue,
    notifyRecordUpdateAvailable
} from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOffers from '@salesforce/apex/OfferController.getOffers';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import approveOffer from '@salesforce/apex/OfferController.approveOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';
import rejectOffer from '@salesforce/apex/OfferController.rejectOffer';
import PRICE_FIELD from '@salesforce/schema/Property__c.Price__c';
import STATUS_FIELD from '@salesforce/schema/Property__c.Status__c';
import { reduceErrors } from 'c/ldsUtils';

export const APPROVAL_THRESHOLD = 10;
const CLOSED_PROPERTY_STATUSES = ['Contracted', 'Under Agreement', 'Closed'];
const OPEN_OFFER_STATUSES = ['Submitted', 'Needs Approval', 'Approved'];
const BADGE_CLASSES = {
    Submitted: 'slds-badge',
    'Needs Approval': 'slds-badge slds-theme_warning',
    Approved: 'slds-badge slds-badge_inverse',
    Accepted: 'slds-badge slds-theme_success',
    Rejected: 'slds-badge slds-theme_error'
};
const ACTIONS = {
    approve: { apex: approveOffer, message: 'Offer approved' },
    accept: { apex: acceptOffer, message: 'Offer accepted' },
    reject: { apex: rejectOffer, message: 'Offer rejected' }
};

/**
 * Percent below asking rounded half-up to one decimal place, matching
 * OfferService.calculatePercentBelowAsking in Apex.
 */
export function percentBelowAsking(askingPrice, amount) {
    if (!askingPrice || askingPrice <= 0 || !amount) {
        return null;
    }
    // toPrecision trims binary floating point noise before rounding.
    const raw = Number(
        (((askingPrice - amount) * 100) / askingPrice).toPrecision(12)
    );
    return (Math.sign(raw) * Math.round(Math.abs(raw) * 10)) / 10;
}

export default class PropertyOffers extends LightningElement {
    @api recordId;

    buyerName = '';
    amount;
    isWorking = false;
    wiredOffers;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [PRICE_FIELD, STATUS_FIELD]
    })
    property;

    @wire(getOffers, { propertyId: '$recordId' })
    wireOffers(result) {
        this.wiredOffers = result;
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

    get canApprove() {
        return this.wiredOffers?.data?.canApprove === true;
    }

    get errorMessage() {
        const error = this.wiredOffers?.error || this.property?.error;
        return error ? reduceErrors(error).join(', ') : null;
    }

    get offers() {
        const offers = this.wiredOffers?.data?.offers || [];
        const propertyOpen = !this.isPropertyClosed;
        return offers.map((offer) => {
            const isOpen = OPEN_OFFER_STATUSES.includes(offer.Status__c);
            return {
                ...offer,
                percentLabel: this.formatPercent(offer.Percent_Below_Asking__c),
                badgeClass: BADGE_CLASSES[offer.Status__c] || 'slds-badge',
                showApprove:
                    this.canApprove && offer.Status__c === 'Needs Approval',
                showAccept:
                    propertyOpen &&
                    (offer.Status__c === 'Submitted' ||
                        offer.Status__c === 'Approved'),
                showReject: isOpen
            };
        });
    }

    get hasOffers() {
        return this.offers.length > 0;
    }

    get cardTitle() {
        return `Offers (${this.offers.length})`;
    }

    get previewPercent() {
        return percentBelowAsking(this.askingPrice, this.amount);
    }

    get hasPreview() {
        return this.previewPercent !== null && this.amount > 0;
    }

    get previewNeedsApproval() {
        return this.hasPreview && this.previewPercent > APPROVAL_THRESHOLD;
    }

    get previewLabel() {
        const percent = this.previewPercent;
        if (percent < 0) {
            return `${Math.abs(percent).toFixed(1)}% above asking`;
        }
        const suffix = this.previewNeedsApproval
            ? ', needs broker approval'
            : '';
        return `${percent.toFixed(1)}% below asking${suffix}`;
    }

    get previewClass() {
        return this.previewNeedsApproval
            ? 'slds-text-color_error slds-text-body_small'
            : 'slds-text-color_weak slds-text-body_small';
    }

    get submitDisabled() {
        return (
            this.isWorking ||
            this.isPropertyClosed ||
            !this.buyerName.trim() ||
            !(this.amount > 0)
        );
    }

    formatPercent(value) {
        if (value === null || value === undefined) {
            return '';
        }
        return value < 0
            ? `${Math.abs(value).toFixed(1)}% above asking`
            : `${Number(value).toFixed(1)}% below asking`;
    }

    handleBuyerChange(event) {
        this.buyerName = event.target.value || '';
    }

    handleAmountChange(event) {
        const value = event.target.value;
        this.amount =
            value === '' || value === null ? undefined : Number(value);
    }

    async handleSubmit() {
        this.isWorking = true;
        try {
            const offer = await submitOffer({
                propertyId: this.recordId,
                buyerName: this.buyerName,
                amount: this.amount
            });
            this.buyerName = '';
            this.amount = undefined;
            this.toast(
                'success',
                offer.Status__c === 'Needs Approval'
                    ? 'Offer submitted: needs broker approval'
                    : 'Offer submitted'
            );
            await this.refresh();
        } catch (error) {
            this.toast('error', reduceErrors(error).join(', '));
        } finally {
            this.isWorking = false;
        }
    }

    async handleAction(event) {
        const action = ACTIONS[event.target.dataset.action];
        const offerId = event.target.dataset.id;
        this.isWorking = true;
        try {
            await action.apex({ offerId });
            this.toast('success', action.message);
            await this.refresh();
        } catch (error) {
            this.toast('error', reduceErrors(error).join(', '));
        } finally {
            this.isWorking = false;
        }
    }

    async refresh() {
        await refreshApex(this.wiredOffers);
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    }

    toast(variant, title) {
        this.dispatchEvent(new ShowToastEvent({ title, variant }));
    }
}
